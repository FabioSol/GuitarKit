//
//  MetronomeViewModel.swift
//  GuitarKit — Metronome tool
//
//  The observable state behind the Metronome face. It owns the drift-free
//  `MetronomeEngine` (the real audio) and exposes the handful of values the UI
//  binds to: the tempo (`bpm`), whether it's running (`isPlaying`), and which
//  beat is currently lit in the beat-ring (`currentBeat`). It also turns the
//  user's tap-tempo taps into a BPM via the PURE `TapTempo` helper.
//
//  WHY A VIEW MODEL AT ALL?
//  The view should stay declarative — "draw a dial showing `bpm`, a ring lit at
//  `currentBeat`" — and not juggle audio sessions, restart logic, or timers. All
//  of that imperative bookkeeping lives here, behind named methods (`start`,
//  `stop`, `nudge`, `registerTap`) the view calls on gestures.
//
//  TWO THINGS THE ORCHESTRATOR SHOULD KNOW (documented inline below too):
//  1. The engine applies a new `bpm` only on the NEXT `start()`. So when the user
//     changes tempo WHILE playing, we restart (stop + start) to make it audible
//     immediately. See `applyBPMChangeWhilePlaying()`.
//  2. The engine doesn't publish "which beat is playing right now," and we don't
//     want to touch it. So the beat-ring is driven by a SEPARATE, display-only
//     counter advanced by a `Task` that sleeps one beat-duration at a time. That
//     counter is cosmetic — a tiny visual drift vs. the real audio is acceptable.
//

import Observation
import Foundation

@MainActor
@Observable
final class MetronomeViewModel {

    // MARK: - Tempo bounds

    /// The clamp range for the dial, matching the spec and `TapTempo`. Exposed so
    /// the view can map a drag distance into this range too.
    static let minBPM: Double = 30
    static let maxBPM: Double = 300

    // MARK: - Public, observed state (what the UI binds to)

    /// Tempo in beats per minute. The setter CLAMPS to 30–300 so no input path
    /// (drag, tap, stepper, VoiceOver) can ever push it out of range, and — if we
    /// happen to be playing — restarts the engine so the new tempo is heard at
    /// once (the engine only picks up `bpm` on `start()`).
    var bpm: Double = 120 {
        didSet {
            // Clamp first. We compare against the *clamped* value so we don't
            // recurse forever (setting `bpm` here would re-enter `didSet`).
            let clamped = min(max(bpm, Self.minBPM), Self.maxBPM)
            if clamped != bpm {
                bpm = clamped       // re-enters didSet once; next time clamped == bpm
                return
            }
            // Only react when the value actually changed, to avoid needless
            // engine restarts when something sets the same value.
            guard oldValue != bpm else { return }
            pushConfigAndRestartIfPlaying()
        }
    }

    /// Whether the click is currently running. Mirrors the engine's own
    /// `isPlaying`; we keep our own copy because the view observes THIS object.
    private(set) var isPlaying = false

    /// Which beat in the bar is lit right now (0 = the downbeat). Drives the
    /// beat-ring highlight. Display-only — see the class header and `beatTask`.
    private(set) var currentBeat = 0

    /// The chosen time signature. Setting it RESIZES `beatAccents` and the
    /// beat-ring (since `beatsPerBar` now comes from here, not a constant) and —
    /// if playing — restarts the engine so the new bar is heard at once.
    var timeSignature: TimeSignature = .fourFour {
        didSet {
            guard oldValue != timeSignature else { return }
            resizeAccents(to: timeSignature.beatsPerBar)
            pushConfigAndRestartIfPlaying()
        }
    }

    /// How finely each beat is subdivided (quarter / eighth / triplet /
    /// sixteenth). Changing it pushes to the engine and restarts if playing.
    var subdivision: Subdivision = .quarter {
        didSet {
            guard oldValue != subdivision else { return }
            pushConfigAndRestartIfPlaying()
        }
    }

    /// The selected click timbre. Restarts the engine (which rebuilds its role
    /// buffers) if playing.
    var soundSet: MetronomeSoundSet = .classic {
        didSet {
            guard oldValue != soundSet else { return }
            pushConfigAndRestartIfPlaying()
        }
    }

    /// Whether the per-beat haptic fires. With everything muted, this is the
    /// SILENT-PRACTICE mode: you feel and see the pulse with no audible click.
    /// Default off. Restarts (cheap) so the engine warms its Taptic generator.
    var hapticsEnabled = false {
        didSet {
            guard oldValue != hapticsEnabled else { return }
            pushConfigAndRestartIfPlaying()
        }
    }

    /// Per-beat emphasis, one entry per beat (index 0 = the downbeat). The view
    /// reads this to draw each dot's state and calls `cycleAccent(at:)` to change
    /// it. `private(set)` — only our methods mutate it, keeping it sized to the
    /// time signature. Defaults to "accent the 1, normal the rest."
    private(set) var beatAccents: [BeatAccent] = [.accent, .normal, .normal, .normal]

    /// How many beats make up one bar (one full trip around the beat-ring). Now
    /// DERIVED from the time signature rather than a constant, so changing the
    /// signature redraws the ring and resizes the accents.
    var beatsPerBar: Int { timeSignature.beatsPerBar }

    // MARK: - Collaborators (plumbing, not observed)

    /// The real, drift-free click engine. `@ObservationIgnored` because the view
    /// observes our published `bpm`/`isPlaying`/`currentBeat`, never the engine
    /// directly — and we deliberately don't want SwiftUI tracking the engine.
    @ObservationIgnored private let engine = MetronomeEngine()

    /// Owns the shared audio session. We must switch it to PLAYBACK before
    /// starting, or the click could be silenced by the ring/silent switch (same
    /// pattern `ScalesViewModel` uses for its tone playback).
    @ObservationIgnored private let coordinator = AudioSessionCoordinator()

    /// The pure tap-tempo estimator. `var` because each tap mutates it.
    @ObservationIgnored private var tapTempo = TapTempo()

    /// The cosmetic beat-ring driver. Cancelled on stop/shutdown. Optional
    /// because there's no task when we're stopped.
    @ObservationIgnored private var beatTask: Task<Void, Never>?

    init() {}

    // MARK: - Transport (start / stop / toggle)

    /// Start the click at the current tempo and begin animating the beat-ring.
    func start() {
        guard !isPlaying else { return }

        // Make the speaker audible regardless of the silent switch. `try?` —
        // a refused session just means a quiet click, not a crash (matches the
        // ScalesViewModel playback pattern).
        try? coordinator.configureForPlayback()

        pushConfig()            // copy bpm + all config into the engine
        engine.start()          // the engine reads its config on start()
        isPlaying = true

        startBeatRing()
    }

    /// Copy the whole current configuration into the engine. The engine reads
    /// these on `start()`, so we call this just before starting (and on any
    /// config change while playing, followed by a restart).
    private func pushConfig() {
        engine.bpm = bpm
        engine.beatsPerBar = beatsPerBar
        engine.subdivision = subdivision
        engine.accents = beatAccents
        engine.soundSet = soundSet
        engine.hapticsEnabled = hapticsEnabled
    }

    /// Stop the click and freeze the beat-ring.
    func stop() {
        guard isPlaying else { return }
        engine.stop()
        isPlaying = false
        stopBeatRing()
    }

    /// Convenience for the single play/stop button.
    func toggle() {
        isPlaying ? stop() : start()
    }

    // MARK: - Tempo inputs

    /// Nudge the tempo by `delta` BPM (the ±1 steppers and the VoiceOver
    /// adjustable action both call this). Clamping happens in `bpm`'s setter.
    func nudge(by delta: Double) {
        bpm += delta
    }

    /// Register a tap-tempo tap "now" and, if the taps imply a tempo, adopt it.
    /// The PURE `TapTempo` does the math (averaging recent intervals, resetting
    /// on a long gap, clamping 30–300); we just feed it a timestamp and apply
    /// whatever BPM it returns.
    func registerTap() {
        // `systemUptime` is a monotonic clock (never jumps backward like wall
        // time can), which is exactly what interval math wants.
        let now = ProcessInfo.processInfo.systemUptime
        if let estimated = tapTempo.register(at: now) {
            // Round to a whole BPM — tap tempo is inherently approximate, and a
            // clean integer reads better on the dial. Setting `bpm` clamps and,
            // if playing, restarts the engine so the new tempo is heard at once.
            bpm = estimated.rounded()
        }
    }

    // MARK: - Teardown

    /// Stop everything and release the audio session. The view calls this from
    /// `.onDisappear` so leaving the Metronome tool doesn't leave a click running
    /// or hold the audio session away from other tools/apps.
    func shutdown() {
        stopBeatRing()
        engine.shutdown()
        isPlaying = false
        coordinator.deactivate()
    }

    // MARK: - Config inputs (time signature / subdivision / accents / sound / haptics)

    /// Choose a time signature (preset or custom). Goes through the observed
    /// `timeSignature` setter, which resizes the accents + ring and restarts the
    /// engine if playing.
    func setTimeSignature(_ signature: TimeSignature) {
        timeSignature = signature
    }

    /// Choose a custom bar by beat count, keeping a quarter-note value. The
    /// `TimeSignature` initializer clamps the count to a sane range.
    func setCustomBeats(_ beats: Int) {
        timeSignature = TimeSignature(beatsPerBar: beats)
    }

    /// Choose a subdivision. Goes through the observed setter (push + restart).
    func setSubdivision(_ value: Subdivision) {
        subdivision = value
    }

    /// Choose a sound set. Goes through the observed setter (push + restart).
    func setSoundSet(_ value: MetronomeSoundSet) {
        soundSet = value
    }

    /// Turn the per-beat haptic on/off (silent practice when sounds are muted).
    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
    }

    /// Tap a beat-ring dot: cycle its accent accent → normal → muted → accent.
    /// Pure cycle lives in `BeatAccent.next`; we just apply it and re-push.
    func cycleAccent(at beatIndex: Int) {
        guard beatAccents.indices.contains(beatIndex) else { return }
        beatAccents[beatIndex] = beatAccents[beatIndex].next
        pushConfigAndRestartIfPlaying()
    }

    /// Resize `beatAccents` to `count` beats when the time signature changes,
    /// PRESERVING existing per-beat choices where possible. Shrinking keeps the
    /// first `count` choices; growing keeps what's there and pads the new beats
    /// with `.normal`. (The initial array already accents beat 0, and we never
    /// shrink to empty for a valid signature, so the downbeat accent is retained
    /// across resizes.)
    private func resizeAccents(to count: Int) {
        guard count > 0 else { beatAccents = []; return }
        if count <= beatAccents.count {
            // Shrinking (or same): keep the first `count` choices.
            beatAccents = Array(beatAccents.prefix(count))
        } else {
            // Growing: keep what we have, pad the new beats with `.normal`.
            let added = Array(repeating: BeatAccent.normal, count: count - beatAccents.count)
            beatAccents = beatAccents + added
        }
    }

    // MARK: - Push-and-restart on any config change while playing

    /// The engine adopts configuration only on `start()`. So if ANYTHING the
    /// engine cares about (tempo, time signature, subdivision, accents, sound
    /// set, haptics) changes while we're already playing, push the new config and
    /// restart it (stop → start) so the change is audible immediately. (When not
    /// playing there's nothing to restart — the config will be read on the next
    /// manual start.)
    ///
    /// ROUGH EDGE the orchestrator should weigh: restarting snaps the click back
    /// to beat 0 (an immediate downbeat). During a fast tempo drag — or rapidly
    /// tapping several dots — the click re-triggers on each step, which can sound
    /// stuttery. It's the simplest correct behavior given the engine's "applies
    /// on next start" contract; a future refinement could debounce or teach the
    /// engine to reconfigure live.
    private func pushConfigAndRestartIfPlaying() {
        guard isPlaying else { return }
        engine.stop()
        pushConfig()
        engine.start()
        // Restart the visual ring too so the dot snaps back to the downbeat in
        // step with the audio (and so it honors a new `beatsPerBar`).
        startBeatRing()
    }

    // MARK: - Cosmetic beat-ring driver
    //
    // IMPORTANT: this is PURELY VISUAL. The engine is the source of audio truth
    // and stays drift-free; this loop just lights ring dots roughly in time. We
    // sleep one beat-duration (60 / bpm seconds) between advances. Because
    // `Task.sleep` is at the mercy of the scheduler (not the audio clock), the
    // lit dot can drift a hair from the actual click over a long run — acceptable
    // for a decorative highlight, and we restart it whenever the tempo changes so
    // it never wanders far.

    /// Begin (or restart) the beat-ring animation from the downbeat.
    private func startBeatRing() {
        stopBeatRing()
        currentBeat = 0
        beatTask = Task { @MainActor [weak self] in
            // Loop until the task is cancelled (stop/shutdown/restart) or the VM
            // is gone. `[weak self]` so a lingering task can't keep the VM alive.
            while !Task.isCancelled {
                guard let self, self.isPlaying else { break }
                // Sleep one beat at the CURRENT tempo. Reading `bpm` each
                // iteration means a tempo change naturally lengthens/shortens
                // the next gap even before a restart kicks in.
                let secondsPerBeat = 60.0 / self.bpm
                try? await Task.sleep(for: .seconds(secondsPerBeat))
                if Task.isCancelled { break }
                guard self.isPlaying else { break }
                // Advance to the next dot, wrapping at the end of the bar.
                self.currentBeat = (self.currentBeat + 1) % self.beatsPerBar
            }
        }
    }

    /// Cancel the beat-ring animation and reset the highlight to the downbeat.
    private func stopBeatRing() {
        beatTask?.cancel()
        beatTask = nil
        currentBeat = 0
    }
}
