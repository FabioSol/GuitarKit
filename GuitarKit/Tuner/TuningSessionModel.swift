//
//  TuningSessionModel.swift
//  GuitarKit
//
//  The thin, observable bridge between the live pitch detector and the pure
//  `TuningSession` state machine. It does three jobs and nothing else:
//    1. build the string targets for the active tuning,
//    2. feed each detector reading + a timestamp into the session,
//    3. expose the session's state to SwiftUI (and pass taps back in).
//
//  Keeping the real logic in `TuningSession` (pure, unit-tested) and only the
//  plumbing here is deliberate: this class touches the clock and the main actor,
//  so it's the part we DON'T unit-test — there's nothing here worth testing that
//  isn't already covered by the state-machine tests.
//

import QuartzCore   // CACurrentMediaTime — a monotonic clock for hold timing
import Observation

@MainActor
@Observable
final class TuningSessionModel {

    // MARK: The wrapped state machine

    /// The pure session. Mutating it (via `ingest`/`lock`) is what drives the
    /// `@Observable` updates SwiftUI re-renders on. Read-only forwarding
    /// properties below expose just what the view needs.
    @ObservationIgnored private var session: TuningSession

    // MARK: Collaborators

    /// A monotonic clock, injected so previews/tests could supply a fake. We use
    /// `CACurrentMediaTime` (seconds since boot, never jumps) rather than wall
    /// time, since the hold logic only cares about *elapsed* seconds.
    @ObservationIgnored private let now: () -> TimeInterval

    // MARK: Init

    /// - Parameters:
    ///   - tuning: open-string notes (low → high). Defaults to standard guitar
    ///     until the Instruments/Presets slice (#09) supplies real ones.
    ///   - calculator: tuning context (reference pitch, temperament) used to
    ///     derive each string's target frequency.
    ///   - tolerance: thresholds/timing (dev-config).
    ///   - now: clock source (injectable).
    init(
        tuning: [Note] = BuiltInTuning.standardGuitar,
        calculator: PitchCalculator = PitchCalculator(),
        tolerance: TuningTolerance = .standard,
        now: @escaping () -> TimeInterval = { CACurrentMediaTime() }
    ) {
        // Derive a target (note + frequency) for every open string, in order.
        let targets = calculator.targets(for: tuning)
        self.session = TuningSession(targets: targets, tolerance: tolerance)
        self.now = now
    }

    // MARK: Inputs

    /// Feed one detector reading (or `nil` for silence) into the session, stamped
    /// with the current time. Called whenever `detector.reading` changes.
    func ingest(_ reading: PitchReading?) {
        session.update(detectedFrequency: reading?.frequency, at: now())
        // A string that just latched is available at `session.justLatchedStringIndex`
        // — a later slice (#06) hooks a haptic/flourish here.
    }

    /// The player tapped a string indicator: lock onto it (override auto-detect).
    func lock(toStringIndex index: Int) {
        session.lock(toStringIndex: index)
    }

    /// Start a brand-new session over the same tuning (e.g. on re-entering the
    /// Tuner) — clears all latches and live state.
    func reset() {
        session = TuningSession(targets: session.targets, tolerance: session.tolerance)
    }

    // MARK: Outputs (forwarded for the view)

    /// All string targets, in order, for rendering the indicator row.
    var targets: [PitchTarget] { session.targets }
    /// The string currently being tuned, if any.
    var activeStringIndex: Int? { session.activeStringIndex }
    /// Signed cents from the active target (+ sharp / − flat), or nil.
    var deviationCents: Double? { session.deviationCents }
    /// The classified zone (flat/sharp/inTune/perfect) of the active reading.
    var zone: TuningZone? { session.zone }
    /// The gentle "tune this next" hint.
    var suggestedStringIndex: Int? { session.suggestedStringIndex }
    /// Whether every string is latched.
    var isComplete: Bool { session.isComplete }

    /// Whether a given string has latched in tune.
    func isLatched(_ index: Int) -> Bool { session.isLatched(index) }
}
