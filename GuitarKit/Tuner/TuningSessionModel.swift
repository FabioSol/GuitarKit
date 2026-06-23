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

    /// Produces the haptic feedback. Behind a protocol so previews/tests can pass
    /// a silent fake. The *timing* of each buzz is decided by the pure
    /// `tuningFeedbackEvent(...)` + the session's latch/complete signals below.
    @ObservationIgnored private let haptics: TuningHapticsProviding

    /// Whether haptics are on. Defaults to true; the Settings slice (#22) wires
    /// this to the user's Feedback preference.
    @ObservationIgnored var hapticsEnabled = true

    // MARK: Transition tracking (to fire each event exactly once)

    /// The active string's zone on the previous `ingest`, so we can detect the
    /// moment it *changes* (e.g. flat → in-tune) rather than firing every frame.
    @ObservationIgnored private var previousZone: TuningZone?

    /// Whether the session was complete on the previous `ingest`, so the
    /// completion flourish fires once on the false → true edge.
    @ObservationIgnored private var wasComplete = false

    // MARK: Init

    /// - Parameters:
    ///   - tuning: open-string notes (low → high). Defaults to standard guitar
    ///     until the Instruments/Presets slice (#09) supplies real ones.
    ///   - calculator: tuning context (reference pitch, temperament) used to
    ///     derive each string's target frequency.
    ///   - tolerance: thresholds/timing (dev-config).
    ///   - now: clock source (injectable).
    init(
        tuning: [Note]? = nil,
        calculator: PitchCalculator? = nil,
        tolerance: TuningTolerance? = nil,
        now: @escaping () -> TimeInterval = { CACurrentMediaTime() },
        haptics: TuningHapticsProviding? = nil
    ) {
        // Resolve the pure-value defaults HERE inside the @MainActor init. As
        // default *arguments* these would be evaluated in a non-isolated context
        // and warn, because this project defaults types to main-actor isolation.
        let tuning = tuning ?? BuiltInTuning.standardGuitar
        let calculator = calculator ?? PitchCalculator()
        let tolerance = tolerance ?? .standard

        // Derive a target (note + frequency) for every open string, in order.
        let targets = calculator.targets(for: tuning)
        self.session = TuningSession(targets: targets, tolerance: tolerance)
        self.now = now
        // Default to the real device-backed haptics. We build it HERE (inside the
        // @MainActor init) rather than as a default argument, because default
        // argument expressions are evaluated in a non-isolated context where a
        // @MainActor initializer can't be called.
        let haptics = haptics ?? TuningHaptics()
        self.haptics = haptics
        haptics.prepare()
    }

    // MARK: Inputs

    /// Feed one detector reading (or `nil` for silence) into the session, stamped
    /// with the current time. Called whenever `detector.reading` changes. Also
    /// fires the matching haptics on each milestone transition.
    func ingest(_ reading: PitchReading?) {
        session.update(detectedFrequency: reading?.frequency, at: now())
        fireHaptics()
    }

    /// Translate this update's state transitions into haptics — each fired once,
    /// on the edge, using the pure `tuningFeedbackEvent` rule for the zone ticks
    /// and the session's own one-shot/edge signals for latch + completion.
    private func fireHaptics() {
        defer {
            // Remember this update's state for next time's edge detection.
            previousZone = session.zone
            wasComplete = session.isComplete
        }
        guard hapticsEnabled else { return }

        // 1) Zone arrival ticks (in-tune vs the distinct perfect).
        switch tuningFeedbackEvent(from: previousZone, to: session.zone) {
        case .enteredPerfect: haptics.perfect()
        case .enteredInTune:  haptics.inTune()
        case nil:             break
        }

        // 2) A string just latched (hold-to-confirm completed) — one-shot signal.
        if session.justLatchedStringIndex != nil {
            haptics.stringLatched()
        }

        // 3) The whole session just completed — fire the flourish on the edge.
        if session.isComplete, !wasComplete {
            haptics.sessionCompleted()
        }
    }

    /// The player tapped a string indicator: lock onto it (override auto-detect).
    func lock(toStringIndex index: Int) {
        session.lock(toStringIndex: index)
    }

    /// Start a brand-new session over the same tuning (e.g. on re-entering the
    /// Tuner) — clears all latches and live state.
    func reset() {
        session = TuningSession(targets: session.targets, tolerance: session.tolerance)
        previousZone = nil
        wasComplete = false
    }

    // MARK: Outputs (forwarded for the view)

    /// The headstock description for the active instrument (art + peg anchors).
    /// Standard guitar for now; the Instruments slice (#09) makes this vary per
    /// selected instrument. Loaded from the bundled JSON, procedural fallback.
    let headstockSpec: HeadstockSpec = .standardGuitar

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
