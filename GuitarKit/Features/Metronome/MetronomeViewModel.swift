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
            applyBPMChangeWhilePlaying()
        }
    }

    /// Whether the click is currently running. Mirrors the engine's own
    /// `isPlaying`; we keep our own copy because the view observes THIS object.
    private(set) var isPlaying = false

    /// Which beat in the bar is lit right now (0 = the downbeat). Drives the
    /// beat-ring highlight. Display-only — see the class header and `beatTask`.
    private(set) var currentBeat = 0

    /// How many beats make up one bar (one full trip around the beat-ring).
    /// Fixed at 4 for this slice (time signatures are a later feature).
    let beatsPerBar = 4

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

        engine.bpm = bpm        // the engine reads this on start()
        engine.start()
        isPlaying = true

        startBeatRing()
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

    // MARK: - BPM-change-while-playing

    /// The engine only adopts a new `bpm` on `start()`. So if the tempo changes
    /// while we're already playing, restart it (stop → start) so the change is
    /// audible immediately rather than on the next manual start.
    ///
    /// ROUGH EDGE the orchestrator should weigh: restarting snaps the click back
    /// to beat 0 (an immediate downbeat). During a fast drag that means the click
    /// re-triggers on every BPM step, which can sound stuttery. It's the simplest
    /// correct behavior given the engine's "applies on next start" contract; a
    /// future refinement could debounce or teach the engine to retune live.
    private func applyBPMChangeWhilePlaying() {
        guard isPlaying else { return }
        engine.stop()
        engine.bpm = bpm
        engine.start()
        // Restart the visual ring too so the dot snaps back to the downbeat in
        // step with the audio.
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
