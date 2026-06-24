//
//  ClickSound.swift
//  GuitarKit
//
//  The metronome's click, synthesized so we don't need a bundled audio asset.
//  A click is just a very short, percussive blip: a brief high tone with a fast
//  exponential decay (a quick "tick"). The PURE sample math lives in `samples`
//  (testable: bounded, non-silent, decaying); the small `buffer` wrapper turns
//  those samples into an `AVAudioPCMBuffer` the engine can schedule.
//

import AVFoundation

/// A namespace (empty `enum`, like `AudioLevel`) for the click synth.
enum ClickSound {

    // MARK: - Pure samples

    /// Generate the click as raw `Float` samples.
    ///
    /// THE SHAPE: a sine tone at `frequencyHz` multiplied by a fast-falling
    /// exponential envelope `e^(−decay·t)`. The high frequency makes it cut
    /// through; the steep decay makes it a short "tick" rather than a sustained
    /// beep. Everything stays within −1…1 (a sine ×, an envelope ≤ 1).
    ///
    /// - Parameters:
    ///   - sampleRate: output samples per second (e.g. 44100).
    ///   - frequencyHz: the blip pitch. ~1 kHz reads as a crisp tick.
    ///   - durationSeconds: how long the (mostly-decayed) click lasts.
    ///   - decay: exponential decay rate; bigger = shorter/snappier.
    /// - Returns: the click waveform, or `[]` for invalid inputs.
    static func samples(
        sampleRate: Double,
        frequencyHz: Double = 1000,
        durationSeconds: Double = 0.03,
        decay: Double = 150
    ) -> [Float] {
        guard sampleRate > 0, durationSeconds > 0, frequencyHz > 0 else { return [] }

        let count = Int(sampleRate * durationSeconds)
        guard count > 0 else { return [] }

        let phaseStep = 2.0 * Double.pi * frequencyHz / sampleRate
        return (0..<count).map { i in
            let t = Double(i) / sampleRate            // seconds elapsed
            let envelope = exp(-decay * t)            // 1 → 0, fast
            return Float(sin(phaseStep * Double(i)) * envelope)
        }
    }

    // MARK: - Buffer wrapper

    /// Wrap a freshly-synthesized click into an `AVAudioPCMBuffer` in `format`,
    /// writing the same mono click into every channel. Returns `nil` if the
    /// buffer can't be allocated.
    static func buffer(format: AVAudioFormat, frequencyHz: Double = 1000) -> AVAudioPCMBuffer? {
        let mono = samples(sampleRate: format.sampleRate, frequencyHz: frequencyHz)
        guard !mono.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(mono.count)),
              let channelData = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(mono.count)
        // Copy the mono click into each output channel.
        for channel in 0..<Int(format.channelCount) {
            for i in 0..<mono.count {
                channelData[channel][i] = mono[i]
            }
        }
        return buffer
    }
}
