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

    // MARK: - Buffer from raw samples
    //
    // The sound-set generators below produce their own custom waveforms (with
    // per-role frequency/decay/gain). This small helper wraps ANY pre-made
    // `[Float]` into a buffer, so we don't duplicate the channel-copy loop.

    /// Wrap an already-synthesized mono waveform into an `AVAudioPCMBuffer` in
    /// `format`, copying it into every channel. Returns `nil` if the samples are
    /// empty or the buffer can't be allocated.
    static func buffer(format: AVAudioFormat, samples mono: [Float]) -> AVAudioPCMBuffer? {
        guard !mono.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(mono.count)),
              let channelData = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(mono.count)
        for channel in 0..<Int(format.channelCount) {
            for i in 0..<mono.count {
                channelData[channel][i] = mono[i]
            }
        }
        return buffer
    }
}

// MARK: - Curated sound sets (distinct accent / normal / subdivision timbres)
//
// A metronome is far more usable when the three roles SOUND different: you want
// to instantly hear "that was the downbeat" vs "that was a regular beat" vs
// "that was an in-between subdivision," without looking. We achieve that purely
// by SYNTHESIS — each role gets its own pitch (and decay/gain) — so we still
// need no bundled audio files.
//
// THE RECIPE for a clearly-readable hierarchy:
//   accent       → highest pitch, full gain        (cuts through, "this is 1")
//   normal       → a lower pitch, slightly quieter  (the steady pulse)
//   subdivision  → a higher pitch but much quieter  (a faint "tick" between beats)
//
// We offer a few SOUND SETS (timbres) so the player can pick a flavor they like;
// each set just chooses different base frequencies and decays. The roles within
// a set are always kept audibly distinct (different peak frequency), which the
// tests assert.

/// The three jobs a click can do within a bar. The engine looks up the right one
/// per tick (beat vs. subdivision, accented vs. not).
enum ClickRole {
    /// The emphasized beat (usually "1").
    case accent
    /// A regular on-the-beat click.
    case normal
    /// An in-between subdivision click (eighths, triplets, sixteenths).
    case subdivision
}

/// A curated family of click timbres. Picking a set changes the *character* of
/// all three roles together while preserving their accent/normal/subdivision
/// relationship.
///
/// `CaseIterable` so the picker lists them automatically; `Sendable` as it's a
/// plain value.
enum MetronomeSoundSet: CaseIterable, Equatable, Hashable, Sendable {
    /// Clean synthesized sine "beeps" — the classic electronic metronome.
    case classic
    /// Lower, woodier blips with a faster decay — a softer, percussive feel.
    case wood
    /// Bright, snappy digital ticks — higher and crisper than `classic`.
    case digital

    /// A short label for the picker.
    var label: String {
        switch self {
        case .classic: return "Classic"
        case .wood:    return "Wood"
        case .digital: return "Digital"
        }
    }

    // MARK: Per-role synthesis parameters

    /// The (frequency, decay, gain) recipe for one role in this set. Bundled in a
    /// tiny tuple-struct so the generator below reads cleanly.
    private struct Voice {
        let frequencyHz: Double
        let decay: Double
        /// A peak amplitude ≤ 1; this is how we make normal/subdivision quieter
        /// than the accent without clipping.
        let gain: Double
    }

    /// The voice for a given role in THIS set. Each set keeps the three roles at
    /// clearly different pitches so they're easy to tell apart by ear.
    private func voice(for role: ClickRole) -> Voice {
        switch self {
        case .classic:
            switch role {
            // Accent highest & loudest; normal lower; subdivision higher but soft.
            case .accent:      return Voice(frequencyHz: 1600, decay: 150, gain: 1.0)
            case .normal:      return Voice(frequencyHz: 1000, decay: 150, gain: 0.7)
            case .subdivision: return Voice(frequencyHz: 2000, decay: 220, gain: 0.4)
            }
        case .wood:
            // Lower, woodier, snappier (faster decays).
            switch role {
            case .accent:      return Voice(frequencyHz: 1100, decay: 240, gain: 1.0)
            case .normal:      return Voice(frequencyHz: 700,  decay: 240, gain: 0.7)
            case .subdivision: return Voice(frequencyHz: 1400, decay: 320, gain: 0.4)
            }
        case .digital:
            // Bright and crisp — higher across the board.
            switch role {
            case .accent:      return Voice(frequencyHz: 2400, decay: 180, gain: 1.0)
            case .normal:      return Voice(frequencyHz: 1500, decay: 180, gain: 0.7)
            case .subdivision: return Voice(frequencyHz: 3000, decay: 260, gain: 0.35)
            }
        }
    }

    // MARK: Pure sample generation

    /// Synthesize the waveform for one role in this set, as raw `Float` samples.
    ///
    /// This reuses the exact same decaying-sine shape as `ClickSound.samples`,
    /// just with the role's chosen frequency/decay, then scales by the role's
    /// `gain` so we can make some roles quieter without clipping. Pure and
    /// testable: the tests assert each role is non-silent and that the three
    /// roles peak at different frequencies (i.e. are audibly distinct).
    ///
    /// - Parameters:
    ///   - role: which click (accent / normal / subdivision).
    ///   - sampleRate: output samples per second.
    /// - Returns: the waveform, or `[]` for an invalid sample rate.
    func samples(for role: ClickRole, sampleRate: Double) -> [Float] {
        let v = voice(for: role)
        // Build the base decaying-sine click at this role's pitch/decay…
        let base = ClickSound.samples(sampleRate: sampleRate,
                                      frequencyHz: v.frequencyHz,
                                      decay: v.decay)
        // …then scale by the role's gain so quieter roles sit under the accent.
        // `Float(v.gain)` once, outside the loop, keeps the map tight.
        let g = Float(v.gain)
        return base.map { $0 * g }
    }

    /// Wrap this set's waveform for `role` into an `AVAudioPCMBuffer` in
    /// `format`, ready for the engine to schedule. `nil` if synthesis fails.
    func buffer(for role: ClickRole, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        ClickSound.buffer(format: format,
                          samples: samples(for: role, sampleRate: format.sampleRate))
    }
}
