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

    /// Whether haptics are on. Defaults to true; the Settings screen wires this
    /// to the user's Feedback preference.
    @ObservationIgnored var hapticsEnabled = true

    // MARK: Current instrument / tuning context

    /// Derives target frequencies from the active reference pitch + temperament.
    /// Rebuilt when the user recalibrates reference pitch (see `reconfigure`).
    @ObservationIgnored private var calculator: PitchCalculator

    /// The in-tune thresholds + hold timing in force. Rebuilt when the user
    /// changes the in-tune sensitivity.
    @ObservationIgnored private var tolerance: TuningTolerance

    // MARK: Transition tracking (to fire each event exactly once)

    /// The active string's zone on the previous `ingest`, so we can detect the
    /// moment it *changes* (e.g. flat → in-tune) rather than firing every frame.
    @ObservationIgnored private var previousZone: TuningZone?

    /// Whether the session was complete on the previous `ingest`, so the
    /// completion flourish fires once on the false → true edge.
    @ObservationIgnored private var wasComplete = false

    // MARK: Init

    /// - Parameters:
    ///   - instrument: which instrument to tune. Defaults to the library's
    ///     cold-start default (standard guitar).
    ///   - tuning: which preset to target. Defaults to the instrument's home tuning.
    ///   - referencePitch: A4 calibration (from Settings). Defaults to 440.
    ///   - tolerance: in-tune thresholds + hold timing. Defaults to `.standard`.
    ///   - now: clock source (injectable).
    ///   - haptics: feedback producer (injectable; silent fake for tests/previews).
    init(
        instrument: Instrument? = nil,
        tuning: Tuning? = nil,
        referencePitch: ReferencePitch? = nil,
        tolerance: TuningTolerance? = nil,
        now: @escaping () -> TimeInterval = { CACurrentMediaTime() },
        haptics: TuningHapticsProviding? = nil
    ) {
        // Resolve the pure-value defaults HERE inside the @MainActor init. As
        // default *arguments* these would be evaluated in a non-isolated context
        // and warn, because this project defaults types to main-actor isolation.
        let instrument = instrument ?? InstrumentLibrary.default
        // Fall back to the instrument's home tuning, then to an empty placeholder
        // (never expected — every shipped instrument has tunings).
        let tuning = tuning ?? instrument.defaultTuning
            ?? Tuning(name: "Standard", category: .standard, strings: [])
        let calculator = PitchCalculator(referenceA: referencePitch ?? .standard)
        let tolerance = tolerance ?? .standard

        self.currentInstrument = instrument
        self.currentTuning = tuning
        self.calculator = calculator
        self.tolerance = tolerance
        self.headstockSpec = Self.spec(for: instrument)

        // Derive a target (note + frequency) for every open string, in order.
        // Cold start has no capo (`.none`); later changes flow through rebuildSession.
        self.session = TuningSession(targets: calculator.targets(for: tuning.strings, capo: .none),
                                     tolerance: tolerance)
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

    /// Start a brand-new session over the current tuning (e.g. on re-entering the
    /// Tuner) — clears all latches and live state.
    func reset() {
        rebuildSession()
    }

    // MARK: Instrument / tuning selection

    /// Switch to a different instrument (and optionally a specific preset). This
    /// re-renders the headstock (new peg layout/art) and retargets detection to
    /// the new strings — the picker (#10) calls this.
    func select(instrument: Instrument, tuning: Tuning? = nil) {
        currentInstrument = instrument
        currentTuning = tuning ?? instrument.defaultTuning ?? currentTuning
        headstockSpec = Self.spec(for: instrument)
        rebuildSession()
    }

    /// Switch to a different preset on the SAME instrument (headstock unchanged,
    /// targets retargeted).
    func select(tuning: Tuning) {
        currentTuning = tuning
        rebuildSession()
    }

    /// Apply Settings-driven calibration: A4 reference pitch + in-tune tolerance.
    /// Rebuilds the targets so the change takes effect immediately.
    func reconfigure(referencePitch: ReferencePitch, tolerance: TuningTolerance) {
        calculator = PitchCalculator(referenceA: referencePitch)
        self.tolerance = tolerance
        rebuildSession()
    }

    // MARK: Capo

    /// Raise the capo by one fret (clamped 0...12 by `Capo`), shifting every
    /// target up a semitone and retargeting detection. The headstock peg names
    /// automatically show the capo-shifted notes (they read `PitchTarget.note`,
    /// which the calculator already transposes by the capo).
    func incrementCapo() {
        capo = Capo(fret: capo.fret + 1)
        rebuildSession()
    }

    /// Clear the capo back to none.
    func resetCapo() {
        capo = .none
        rebuildSession()
    }

    /// Rebuild the pure session from the current tuning + calculator + tolerance
    /// + capo, clearing latches and the haptic edge-tracking. The single place
    /// targets are (re)derived, so every selection/reconfigure/capo path stays
    /// consistent.
    private func rebuildSession() {
        session = TuningSession(
            targets: calculator.targets(for: currentTuning.strings, capo: capo),
            tolerance: tolerance
        )
        previousZone = nil
        wasComplete = false
    }

    /// Resolve an instrument's headstock spec from its bundled JSON, falling back
    /// to a generic procedural layout (so a missing/!decodable JSON never renders
    /// an empty head).
    private static func spec(for instrument: Instrument) -> HeadstockSpec {
        HeadstockSpec.load(instrument.headstockSpecName)
            ?? HeadstockSpec(
                artAsset: nil,
                aspectRatio: 0.66,
                pegs: HeadstockLayout.generic(stringCount: instrument.stringCount).pegs
            )
    }

    // MARK: Outputs (forwarded for the view)

    /// The active instrument and tuning (observed, so the UI updates on select).
    private(set) var currentInstrument: Instrument
    private(set) var currentTuning: Tuning

    /// The headstock description for the active instrument (art + peg anchors).
    /// Updated by `select(instrument:)`, so the hero re-renders per instrument.
    private(set) var headstockSpec: HeadstockSpec

    /// The active capo (semitone shift of every target). Observed so the capo
    /// chip re-renders; mutated only via `incrementCapo()`/`resetCapo()`.
    private(set) var capo: Capo = .none

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
