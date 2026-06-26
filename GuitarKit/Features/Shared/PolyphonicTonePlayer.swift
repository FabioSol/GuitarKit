//
//  PolyphonicTonePlayer.swift
//  GuitarKit — shared tool support
//
//  A polyphonic audio player for the Chords tool's "block chord" playback.
//  Runs up to `maxVoices` harmonic oscillators inside a single
//  `AVAudioSourceNode` render closure, summing them together so all notes of a
//  chord sound simultaneously — the true-polyphony counterpart to
//  `ToneGenerator`'s single-voice "tap a peg" design.
//
//  DESIGN: same `nonisolated(unsafe)` discipline as `ToneGenerator` and
//  `AudioInputEngine`. All render-state fields are `nonisolated(unsafe)`; the
//  main actor hands off new pitches via scalar `targetPhaseSteps[i]` writes
//  (Float = word-sized, can't tear) and the render callback applies them.
//  The main actor writes to `generators` only before the engine starts, when the
//  audio thread is not yet running, so there is no concurrent mutation.
//

import AVFoundation

@MainActor
final class PolyphonicTonePlayer {

    // MARK: Constants

    private let maxVoices: Int = 7          // enough for a 7-string guitar
    private let envelopeRate: Float = 0.0005

    // MARK: Engine bookkeeping

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var isEngineRunning = false
    private var sampleRate: Double = 44_100

    /// Scheduled by `stop()` to tear down the engine after the fade-out completes.
    /// Cancelled by `play()` if playback resumes before the engine shuts down.
    private var stopTask: Task<Void, Never>?

    // MARK: Audio-thread state
    //
    // The main actor writes `targetPhaseSteps[i]` and `envelopeTargets[i]` from
    // `play(frequencies:)` — both are Floats (word-sized), so a cross-thread
    // write can never produce a torn read on the audio side. `generators`,
    // `appliedPhaseSteps`, and `envelopeGains` are exclusively touched by the
    // render callback after the engine starts.

    nonisolated(unsafe) private var generators: [ToneOscillator.Generator]
    nonisolated(unsafe) private var targetPhaseSteps: [Float]
    nonisolated(unsafe) private var appliedPhaseSteps: [Float]
    nonisolated(unsafe) private var envelopeGains: [Float]
    nonisolated(unsafe) private var envelopeTargets: [Float]
    // Normalisation: 1 / (number of active voices), updated each play() call so
    // the summed output always matches the single-voice ToneGenerator's volume.
    nonisolated(unsafe) private var mixGain: Float = 1.0

    init() {
        let n = 7
        generators        = (0..<n).map { _ in ToneOscillator.Generator(frequencyHz: 0, sampleRate: 44_100) }
        targetPhaseSteps  = Array(repeating: Float(0),  count: n)
        appliedPhaseSteps = Array(repeating: Float(-1), count: n)
        envelopeGains     = Array(repeating: Float(0),  count: n)
        envelopeTargets   = Array(repeating: Float(0),  count: n)
    }

    // MARK: Public API

    /// Start all notes simultaneously. Extra notes beyond `maxVoices` are dropped.
    func play(frequencies: [Double]) {
        stopTask?.cancel()  // abort any pending engine shutdown
        do { try startEngineIfNeeded() } catch { return }

        let active = frequencies.prefix(maxVoices)
        // Normalise by actual voice count so the summed output is at full volume
        // regardless of chord size, matching single-voice ToneGenerator's level.
        mixGain = 1.0 / Float(max(1, active.count))
        for (i, freq) in active.enumerated() {
            targetPhaseSteps[i] = ToneOscillator.phaseStep(frequencyHz: freq, sampleRate: sampleRate)
            envelopeTargets[i]  = 1.0
        }
        for i in active.count..<maxVoices {
            envelopeTargets[i] = 0.0
        }
    }

    /// Fade all voices to silence, then stop the engine once the fade completes.
    func stop() {
        for i in 0..<maxVoices { envelopeTargets[i] = 0.0 }
        stopTask?.cancel()
        stopTask = Task { @MainActor [weak self] in
            // 1.0 / envelopeRate ≈ 45ms at 44.1 kHz; 80ms gives a safe margin.
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else { return }
            // Guard against a play() call that arrived between stop() and here.
            let allSilent = (0..<self.maxVoices).allSatisfy { self.envelopeTargets[$0] == 0 }
            guard allSilent else { return }
            self.shutdownEngine()
        }
    }

    private func shutdownEngine() {
        guard isEngineRunning else { return }
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        isEngineRunning = false
    }

    // MARK: Engine setup

    private func startEngineIfNeeded() throws {
        guard !isEngineRunning else { return }

        let output = engine.outputNode
        let fmt = output.outputFormat(forBus: 0)
        sampleRate = fmt.sampleRate

        // Re-init generators at the real hardware sample rate.
        // Safe to write here: the audio thread hasn't started yet.
        generators        = (0..<maxVoices).map { _ in ToneOscillator.Generator(frequencyHz: 0, sampleRate: sampleRate) }
        appliedPhaseSteps = Array(repeating: Float(-1), count: maxVoices)

        let node = makeSourceNode(format: fmt)
        engine.attach(node)
        engine.connect(node, to: output, format: fmt)
        sourceNode = node

        engine.prepare()
        try engine.start()
        isEngineRunning = true
    }

    private func makeSourceNode(format: AVAudioFormat) -> AVAudioSourceNode {
        // Capture constants so the render closure never touches main-actor properties.
        let voiceCount = maxVoices
        let rate       = envelopeRate

        return AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                var mixed: Float = 0

                for i in 0..<voiceCount {
                    // Apply a pending pitch change handed off by play().
                    let step = self.targetPhaseSteps[i]
                    if step != self.appliedPhaseSteps[i] {
                        self.generators[i].setPhaseStep(step)
                        self.appliedPhaseSteps[i] = step
                    }

                    // Smooth the per-voice envelope toward its target.
                    if self.envelopeGains[i] < self.envelopeTargets[i] {
                        self.envelopeGains[i] = min(self.envelopeGains[i] + rate, self.envelopeTargets[i])
                    } else if self.envelopeGains[i] > self.envelopeTargets[i] {
                        self.envelopeGains[i] = max(self.envelopeGains[i] - rate, self.envelopeTargets[i])
                    }

                    mixed += self.generators[i].nextSample() * self.envelopeGains[i]
                }

                // Scale by 1/activeVoices so the summed chord is at full volume.
                let sample = mixed * self.mixGain
                for buffer in buffers {
                    buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }

            return noErr
        }
    }
}
