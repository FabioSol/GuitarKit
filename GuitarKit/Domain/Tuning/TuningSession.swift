//
//  TuningSession.swift
//  GuitarKit
//
//  The PURE state machine behind targeted tuning. It knows nothing about audio
//  hardware, timers, or SwiftUI — you feed it a detected frequency and the
//  current time, and it tells you which string you're tuning, how far off you
//  are, and when a string has been confirmed "in tune". That hardware-free shape
//  is what lets us unit-test the whole tuning *behavior* with scripted pitch
//  sequences (PRD testing decision), instead of needing a mic and a stopwatch.
//
//  THE BEHAVIOR IT ENCODES (PRD stories 3–9):
//    • auto-detect the nearest target string from whatever you play,
//    • report deviation in cents WITH direction (flat/sharp),
//    • let you tap-to-LOCK a target so a wildly out-of-tune string isn't matched
//      to the wrong note,
//    • require you to HOLD in tolerance briefly before it latches (so the
//      readout doesn't flicker as you pass through pitch),
//    • LATCH each confirmed string green and keep it green for the session,
//    • report COMPLETION when every string is latched.
//

import Foundation

// MARK: - Tuning zone (how flat/sharp, classified)

/// A classification of the current deviation. Direction (`flat`/`sharp`) tells
/// you which way to turn the peg; closeness (`inTune`/`perfect`) tells you how
/// done you are. Exactly one applies at a time.
///
/// IMPORTANT (accessibility): this is the *position/closeness* channel of the
/// feedback. Color maps onto it later, but the zone itself — and the signed
/// cents — convey the state without relying on color (PRD story 13).
public enum TuningZone: Equatable, Sendable {
    case flat       // below tolerance and too low  → tune up
    case sharp      // above tolerance and too high → tune down
    case inTune     // within the in-tune window (but not yet "perfect")
    case perfect    // within the tighter "perfect" window
}

// MARK: - Tolerances / timing (dev-config knobs)

/// The thresholds and timing that define "in tune". Bundled into one value so
/// they can be tweaked in one place — the PRD wants these (and smoothing) to
/// live behind dev config, so exposing them as a struct keeps them swappable.
public struct TuningTolerance: Equatable, Sendable {
    /// Within ±this many cents counts as in tune (green). PRD: ±3¢.
    public var inTuneCents: Double
    /// Within ±this many cents counts as perfect (tighter). PRD: ±1¢.
    public var perfectCents: Double
    /// How long you must hold within `inTuneCents` before a string latches.
    /// PRD: ~0.5–1 s; 0.7 s is a calm middle.
    public var holdDuration: TimeInterval

    public init(inTuneCents: Double, perfectCents: Double, holdDuration: TimeInterval) {
        self.inTuneCents = inTuneCents
        self.perfectCents = perfectCents
        self.holdDuration = holdDuration
    }

    /// The shipping defaults.
    public static let standard = TuningTolerance(inTuneCents: 3, perfectCents: 1, holdDuration: 0.7)
}

// MARK: - The session

/// A single tuning session over a fixed set of string targets.
///
/// WHY A `struct` (value type)?
/// The session is just data evolving over time — no identity, no shared mutable
/// resources. A struct gives us cheap copies (handy for tests that snapshot a
/// state), value equality, and the guarantee that the only way state changes is
/// through the `mutating` methods below. The owning view-model keeps one
/// instance and mutates it as readings arrive.
public struct TuningSession: Equatable, Sendable {

    // MARK: Fixed configuration

    /// The string targets for the active tuning, in string order (low → high).
    public let targets: [PitchTarget]
    /// The thresholds/timing in force for this session.
    public let tolerance: TuningTolerance

    // MARK: Evolving state (read-only to the outside)

    /// Indices of strings confirmed in tune. Once added, a string stays here for
    /// the whole session — that's what makes "all green" a stable finish line.
    public private(set) var latchedStrings: Set<Int> = []

    /// The string currently being tuned (auto-detected or manually locked), or
    /// `nil` before anything has been played.
    public private(set) var activeStringIndex: Int?

    /// Signed deviation of the latest reading from the active target, in cents
    /// (positive = sharp, negative = flat). `nil` when there's no live reading.
    public private(set) var deviationCents: Double?

    /// Whether the active string was chosen by a manual tap-lock (vs auto-detect).
    public private(set) var isManuallyLocked: Bool = false

    /// The string index that latched on the MOST RECENT `update`, else `nil`.
    /// A one-shot event flag for the UI to fire a haptic / flourish exactly once
    /// (consumed each update). Not part of "latched" — that's `latchedStrings`.
    public private(set) var justLatchedStringIndex: Int?

    // MARK: Private hold tracking

    /// The timestamp at which the active string most recently *entered* the
    /// in-tune window, or `nil` if it isn't currently in tolerance. We latch once
    /// `now − inToleranceSince ≥ holdDuration`. Reset whenever we drift out of
    /// tolerance, change strings, or lose the signal — so the hold must be
    /// *continuous*.
    private var inToleranceSince: TimeInterval?

    // MARK: Init

    public init(targets: [PitchTarget], tolerance: TuningTolerance = .standard) {
        self.targets = targets
        self.tolerance = tolerance
    }

    // MARK: Manual override (tap-to-lock)

    /// Lock onto a specific string so detection stops auto-switching — used when
    /// a string is so far out of tune that "nearest" would match the wrong note.
    /// No-op for an out-of-range index.
    public mutating func lock(toStringIndex index: Int) {
        guard targets.indices.contains(index) else { return }
        isManuallyLocked = true
        activeStringIndex = index
        // Start the hold fresh against the newly-locked target.
        inToleranceSince = nil
        deviationCents = nil
    }

    /// Release a manual lock and return to auto-detect.
    public mutating func clearLock() {
        isManuallyLocked = false
        inToleranceSince = nil
    }

    // MARK: The core step

    /// Advance the machine with the latest detected frequency at time `time`.
    ///
    /// - Parameters:
    ///   - detectedFrequency: the smoothed detected pitch in Hz, or `nil` for
    ///     silence / no-confident-pitch.
    ///   - time: a monotonically increasing timestamp in seconds. Passed in
    ///     (rather than read from a clock here) so tests can script time exactly.
    public mutating func update(detectedFrequency: Double?, at time: TimeInterval) {
        // Clear the one-shot latch event from the previous update.
        justLatchedStringIndex = nil

        // SIGNAL DROPOUT: with no pitch, freeze. We keep `activeStringIndex`
        // sticky so the UI doesn't flicker, but clear the live deviation and stop
        // the hold timer — you must hold *continuously* while sounding to latch.
        guard let frequency = detectedFrequency, frequency > 0 else {
            inToleranceSince = nil
            deviationCents = nil
            return
        }

        // CHOOSE THE TARGET: the locked string if any, otherwise the nearest.
        let index: Int
        if isManuallyLocked, let locked = activeStringIndex {
            index = locked
        } else if let nearest = nearestStringIndex(to: frequency) {
            index = nearest
        } else {
            return // no targets at all
        }

        // If auto-detect moved us to a different string, restart the hold timer.
        if index != activeStringIndex {
            activeStringIndex = index
            inToleranceSince = nil
        }

        // DEVIATION in cents (signed): positive = sharp, negative = flat.
        let cents = PitchCalculator.cents(from: frequency, to: targets[index].frequencyHz)
        deviationCents = cents

        // HOLD-TO-CONFIRM: while within the in-tune window, run the hold timer;
        // once it has been satisfied continuously for `holdDuration`, latch.
        if abs(cents) <= tolerance.inTuneCents {
            if let since = inToleranceSince {
                if time - since >= tolerance.holdDuration {
                    latch(index)
                }
            } else {
                inToleranceSince = time   // just entered tolerance: start the clock
            }
        } else {
            inToleranceSince = nil        // drifted out: hold must restart
        }
    }

    // MARK: Latching

    /// Mark a string confirmed in tune. Idempotent (re-latching is a no-op) and
    /// it clears any manual lock so the player naturally flows to the next string.
    private mutating func latch(_ index: Int) {
        guard !latchedStrings.contains(index) else { return }
        latchedStrings.insert(index)
        justLatchedStringIndex = index
        inToleranceSince = nil
        isManuallyLocked = false
    }

    // MARK: Derived queries

    /// The nearest target to `frequency`, measured in absolute cents (so it's
    /// octave-correct and consistent regardless of register).
    func nearestStringIndex(to frequency: Double) -> Int? {
        guard !targets.isEmpty else { return nil }
        return targets.indices.min { a, b in
            let da = abs(PitchCalculator.cents(from: frequency, to: targets[a].frequencyHz))
            let db = abs(PitchCalculator.cents(from: frequency, to: targets[b].frequencyHz))
            return da < db
        }
    }

    /// Whether a given string has been latched in tune.
    public func isLatched(_ index: Int) -> Bool {
        latchedStrings.contains(index)
    }

    /// True once every string is latched — the "all green" finish line.
    public var isComplete: Bool {
        !targets.isEmpty && latchedStrings.count == targets.count
    }

    /// The gentle next-string nudge: the first not-yet-latched string in tuning
    /// order, or `nil` when complete. The player is free to ignore it.
    public var suggestedStringIndex: Int? {
        targets.indices.first { !latchedStrings.contains($0) }
    }

    /// The current deviation classified into a `TuningZone`, or `nil` with no
    /// live reading.
    public var zone: TuningZone? {
        guard let cents = deviationCents else { return nil }
        if abs(cents) <= tolerance.perfectCents { return .perfect }
        if abs(cents) <= tolerance.inTuneCents { return .inTune }
        return cents < 0 ? .flat : .sharp
    }
}
