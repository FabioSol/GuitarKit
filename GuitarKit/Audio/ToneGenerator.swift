//
//  ToneGenerator.swift
//  GuitarKit
//
//  The real-time PLAYBACK side of the tone generator: it takes the pure samples
//  from `ToneOscillator` and actually pushes them out the speaker through an
//  `AVAudioEngine`. Think of this as the playback twin of `AudioInputEngine`:
//  that class wraps the mic (input); this one wraps an oscillator → output. The
//  pure DSP lives in `ToneOscillator` so it stays unit-testable; THIS class is
//  the thin, hardware-bound, real-time wrapper we deliberately keep small.
//
//  WHAT THE HEADSTOCK TONE-MODE NEEDS (from the PRD):
//    • tap a peg → play that string's target pitch
//    • tap-to-toggle SUSTAIN: tapping the same string again stops it; tapping a
//      different string retargets the already-playing tone
//    • detection pauses while a tone plays (the orchestrator wires that part by
//      stopping the mic; this class just owns the sound)
//
//  HOW WE MAKE SOUND — `AVAudioSourceNode`:
//  An `AVAudioSourceNode` is a node you plug into the engine that PULLS audio
//  from a closure you provide. The audio system calls that closure on a
//  real-time thread whenever it needs more samples, and we fill its buffer from
//  our `ToneOscillator.Generator`. It's the mirror image of `installTap` (which
//  PUSHES mic buffers to us); here we're the source, not the sink.
//

import AVFoundation
import Observation

// MARK: - The tone-playback seam

/// The small surface the tuner needs to play a peg's pitch: start a tone, stop
/// it, fully tear down, and ask what's currently sounding. Behind a protocol so
/// the `TunerCoordinator` (which decides WHEN to play/stop during mode changes)
/// can be unit-tested with a silent fake — no `AVAudioEngine` required.
@MainActor
protocol TonePlaying: AnyObject {
    /// The frequency currently sounding, or `nil` when silent. Drives the
    /// tone-mode peg highlight.
    var currentFrequencyHz: Double? { get }
    /// Start (or retune to) a sustained tone at this frequency.
    func play(frequencyHz: Double)
    /// Stop the current tone but keep the engine warm for the next play.
    func stop()
    /// Stop and release the audio engine entirely (leaving tone-mode).
    func shutdown()
}

/// Plays a single, sustained, harmonic-rich tone through the speaker.
///
/// `@Observable` so SwiftUI can react to `isPlaying` (e.g. to highlight the
/// peg that's currently sounding); `@MainActor` because that published state and
/// the UI binding live on the main thread. The render callback fires on a
/// real-time AUDIO thread — see `makeSourceNode()` for how we keep that thread
/// from touching main-actor state (the `nonisolated(unsafe)` pattern, exactly as
/// in `AudioInputEngine`).
@MainActor
@Observable
final class ToneGenerator: TonePlaying {

    // MARK: Published output

    /// Whether a tone is currently sounding. `private(set)` → this class writes
    /// it, the UI only reads it. SwiftUI re-renders when it flips.
    private(set) var isPlaying: Bool = false

    /// The frequency currently playing (or `nil` when silent). Kept so a second
    /// tap on the SAME pitch can be recognized as "toggle off", while a tap on a
    /// DIFFERENT pitch is recognized as "retarget". `private(set)` for the same
    /// read-only-to-UI reason.
    private(set) var currentFrequencyHz: Double?

    // MARK: Private audio machinery
    //
    // All `@ObservationIgnored`: it's plumbing, not UI state. Observing an
    // `AVAudioEngine` would be meaningless and wasteful (same reasoning as
    // `AudioInputEngine`).

    /// The engine hosting our tiny audio graph (just sourceNode → output).
    @ObservationIgnored private let engine = AVAudioEngine()

    /// The node that pulls samples from our render closure. Created lazily in
    /// `start()` once we know the output's sample rate. Optional because it
    /// doesn't exist until the first `play(...)`.
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?

    /// Guards against double start/stop of the engine, which `AVAudioEngine`
    /// dislikes (same idempotency guard as `AudioInputEngine.isRunning`).
    @ObservationIgnored private var isEngineRunning = false

    /// The output hardware's sample rate, captured when the engine starts. The
    /// oscillator needs it to compute the right phase step for a pitch.
    @ObservationIgnored private var sampleRate: Double = 44_100

    // MARK: Real-time render state
    //
    // CONCURRENCY DISCIPLINE: `generator` is a multi-field struct (phase +
    // phaseStep), so it must be touched by exactly ONE thread. We keep it
    // AUDIO-THREAD-ONLY: the main actor never mutates it. To retarget the pitch,
    // `play(...)` writes a single SCALAR — `targetPhaseStep` — which the render
    // callback reads and applies to the generator on the audio thread. Scalars
    // (Float/Bool) are word-sized, so this hand-off has no torn-read hazard. The
    // main actor never touches `generator` itself — the audio thread mutates its
    // `phase` concurrently, so doing so would be a data race.
    //
    // `nonisolated(unsafe)` is us telling the compiler we've reasoned about the
    // threading (same pattern as `AudioInputEngine`).

    /// The phase-walking sample source. Touched ONLY by the render callback.
    @ObservationIgnored nonisolated(unsafe) private var generator =
        ToneOscillator.Generator(frequencyHz: 0, sampleRate: 44_100)

    /// The pitch hand-off: the main actor (`play`) writes the desired phase step
    /// here; the render callback reads it and retunes `generator`. A single Float,
    /// so the cross-thread write/read can't tear.
    @ObservationIgnored nonisolated(unsafe) private var targetPhaseStep: Float = 0

    /// The phase step the render callback has already applied — AUDIO-THREAD-ONLY,
    /// so the callback only retunes when `targetPhaseStep` actually changed.
    @ObservationIgnored nonisolated(unsafe) private var appliedPhaseStep: Float = -1

    /// The envelope's CURRENT gain (0 = silent … 1 = full). Multiplying every
    /// sample by this and easing it up/down gives a smooth ATTACK (fade-in) and
    /// RELEASE (fade-out) instead of an abrupt edge — abrupt edges in audio cause
    /// an audible "click"/"pop". See `envelopeTarget`.
    @ObservationIgnored nonisolated(unsafe) private var envelopeGain: Float = 0

    /// Where the envelope is heading: `1` while a note should sound, `0` while it
    /// should fade out. The render callback eases `envelopeGain` toward this each
    /// sample, so toggling a note is a quick smooth ramp, not a jump.
    @ObservationIgnored nonisolated(unsafe) private var envelopeTarget: Float = 0

    /// How quickly the envelope approaches its target, per sample. Small = a
    /// gentle fade. At 44.1 kHz, `0.0005` reaches full gain in ~a few
    /// milliseconds — fast enough to feel instant, slow enough to kill the click.
    @ObservationIgnored private let envelopeRate: Float = 0.0005

    /// Scheduled by `stop()` to tear down the engine after the fade-out completes.
    /// Cancelled by `play(...)` if the tone is restarted before the engine shuts down.
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    init() {}

    // MARK: Public API — tap-to-toggle sustain

    /// Play a tone at `frequencyHz`, with TAP-TO-TOGGLE SUSTAIN semantics:
    ///
    ///   • Not currently playing → start sounding this pitch (sustained).
    ///   • Already playing the SAME pitch → stop (the second tap toggles off).
    ///   • Already playing a DIFFERENT pitch → smoothly retarget to the new one
    ///     (tapping another peg switches strings without a click).
    ///
    /// The note sustains indefinitely until toggled off or `stop()`ed — matching
    /// "tap a peg to play that string's target pitch; tap-to-toggle sustain".
    ///
    /// - Parameter frequencyHz: the target pitch (e.g. a `PitchTarget.frequencyHz`).
    func play(frequencyHz: Double) {
        // TOGGLE-OFF: a second tap on the pitch that's already sounding stops it.
        // We compare with a tiny tolerance because frequencies are `Double`s and
        // exact equality on floating point is fragile.
        if isPlaying, let current = currentFrequencyHz,
           abs(current - frequencyHz) < 0.01 {
            stop()
            return
        }

        stopTask?.cancel()  // abort any pending engine shutdown

        // Make sure the engine is up (first play, or after a previous stop).
        do {
            try startEngineIfNeeded()
        } catch {
            // If the speaker path can't start there's nothing audible to do.
            // We fail quietly rather than crash; the UI just won't highlight a
            // playing peg. (The orchestrator owns user-facing error surfacing.)
            return
        }

        // Retune the oscillator to the new pitch — but NOT by touching `generator`
        // (the audio thread owns it). We compute the phase step HERE (sampleRate
        // is known on the main actor) and hand it to the render callback via the
        // scalar `targetPhaseStep`; the callback applies it on the audio thread.
        // Phase isn't reset, so switching strings mid-sustain glides, not pops.
        targetPhaseStep = ToneOscillator.phaseStep(frequencyHz: frequencyHz, sampleRate: sampleRate)

        // Aim the envelope at full volume → the render callback fades the tone IN.
        envelopeTarget = 1

        // Publish UI state on the main actor (we're already on it here).
        currentFrequencyHz = frequencyHz
        isPlaying = true
    }

    /// Stop any sounding tone. Safe to call when nothing is playing.
    ///
    /// Aims the envelope at 0 for a click-free fade-out, then schedules an engine
    /// shutdown ~50 ms later (just past the fade duration of 1/envelopeRate ≈ 45 ms).
    /// Leaving the engine running for that window means a rapid replay starts
    /// instantly; once it's actually idle the engine tears down so it doesn't
    /// compete with concurrent engines (e.g. the polyphonic player or the metronome).
    /// `shutdown()` — called when truly leaving the feature — cancels the task and
    /// tears down immediately.
    func stop() {
        envelopeTarget = 0
        isPlaying = false
        currentFrequencyHz = nil

        stopTask?.cancel()
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, !Task.isCancelled, self.envelopeTarget == 0 else { return }
            self.tearDownEngine()
        }
    }

    /// Fully tear down the engine and release the output. The orchestrator calls
    /// this when LEAVING the Tuner so we don't hold the audio hardware. Cancels
    /// any deferred-stop task and tears down immediately (no waiting for the fade).
    func shutdown() {
        stopTask?.cancel()
        isPlaying = false
        currentFrequencyHz = nil
        tearDownEngine()
    }

    private func tearDownEngine() {
        guard isEngineRunning else { return }
        envelopeGain = 0            // hard-silence before the engine stops
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
        }
        sourceNode = nil
        isEngineRunning = false
    }

    // MARK: Engine setup

    /// Lazily build and start the audio graph the first time we need sound (and
    /// after a `shutdown()`). Idempotent: a no-op if already running.
    ///
    /// NOTE ON THE AUDIO SESSION: this class deliberately does NOT set the
    /// `AVAudioSession` category itself — that's the `AudioSessionCoordinator`'s
    /// job (record↔playback arbitration). The orchestrator switches the session
    /// to `.playback` *before* calling `play(...)`. Keeping session policy in one
    /// place avoids this class and `AudioInputEngine` fighting over it.
    private func startEngineIfNeeded() throws {
        guard !isEngineRunning else { return }

        // The output node's format tells us the hardware sample rate to synth at.
        let output = engine.outputNode
        let outputFormat = output.outputFormat(forBus: 0)
        sampleRate = outputFormat.sampleRate

        // Re-seed the generator at the real sample rate (the init used a default
        // guess). It starts silent (envelopeGain 0), so this is click-free. Safe
        // to write `generator` here: the engine isn't running yet, so no audio
        // thread is touching it. Reset `appliedPhaseStep` so the render callback
        // re-applies the current target on the first frame.
        generator = ToneOscillator.Generator(frequencyHz: 0, sampleRate: sampleRate)
        appliedPhaseStep = -1

        // Build the source node, attach it, and wire it to the speaker.
        let node = makeSourceNode(format: outputFormat)
        engine.attach(node)
        engine.connect(node, to: output, format: outputFormat)
        sourceNode = node

        engine.prepare()
        try engine.start()
        isEngineRunning = true
    }

    /// Create the `AVAudioSourceNode` whose render closure fills each requested
    /// buffer with oscillator samples shaped by the attack/release envelope.
    ///
    /// THREADING: the closure marked `[weak self]` runs on a real-time AUDIO
    /// thread, not the main actor. It must be FAST and allocation-free — so it
    /// only touches the `nonisolated(unsafe)` render state (`generator`,
    /// `envelopeGain`, `envelopeTarget`) and never main-actor properties. This is
    /// the exact discipline `AudioInputEngine`'s tap closure follows.
    private func makeSourceNode(format: AVAudioFormat) -> AVAudioSourceNode {
        // The render block returns `OSStatus`; `noErr` means "I filled the
        // buffer". Its parameters describe how many frames the system wants and
        // where to write them (`AudioBufferList`).
        AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            // If we've been torn down, output silence (zeros) and bail cleanly.
            guard let self else { return noErr }

            // `UnsafeMutableAudioBufferListPointer` wraps the C buffer list as a
            // Swift collection so we can iterate its channels safely.
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            // Apply any pending pitch change handed over by `play(...)` — done
            // HERE (on the audio thread) so `generator` is only ever touched by
            // this thread. Once per buffer, only when it actually changed.
            let step = self.targetPhaseStep
            if step != self.appliedPhaseStep {
                self.generator.setPhaseStep(step)
                self.appliedPhaseStep = step
            }

            // Synthesize one frame at a time. We compute the (mono) sample once,
            // then write it into EVERY output channel (so a stereo speaker hears
            // the same tone on both sides).
            for frame in 0..<Int(frameCount) {
                // Ease the envelope one step toward its target → smooth fades.
                // `envelopeRate` is the per-sample step; `min`/`max` clamp so we
                // land exactly on the target instead of overshooting it.
                if self.envelopeGain < self.envelopeTarget {
                    self.envelopeGain = min(self.envelopeGain + self.envelopeRate,
                                            self.envelopeTarget)
                } else if self.envelopeGain > self.envelopeTarget {
                    self.envelopeGain = max(self.envelopeGain - self.envelopeRate,
                                            self.envelopeTarget)
                }

                // Pure oscillator sample × current envelope gain = final sample.
                let value = self.generator.nextSample() * self.envelopeGain

                // Write that one value into every channel's frame slot.
                for buffer in buffers {
                    // Each `buffer.mData` is a raw pointer; reinterpret it as a
                    // `Float` array view and store this frame's sample.
                    let channel = buffer.mData!.assumingMemoryBound(to: Float.self)
                    channel[frame] = value
                }
            }

            return noErr
        }
    }
}
