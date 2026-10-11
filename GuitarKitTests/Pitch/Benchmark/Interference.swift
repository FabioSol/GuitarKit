//
//  Interference.swift
//  GuitarKitTests
//
//  Synthetic ROOM SOUNDS for the pitch benchmark — the things that confuse a
//  tuner in real life. What matters isn't how LOUD a sound is but how much it
//  looks like a string to the tracker, so the kinds are grouped by that:
//
//    • steady noise   (rumble + hum, fan)  — random, no pitch. The confidence
//                     gate and the band-pass should handle it.
//    • other instruments (another guitar, keyboard chords) — REAL pitches,
//                     harmonic like a string. They pass every gate because
//                     they ARE notes.
//    • speech         — PITCHED: speaking pitch sits at ~85–255 Hz, right in
//                     the low strings' range, gliding, in short syllables.
//    • clicks + knocks — short bursts that can break a tracked note; knocks
//                     and clinks briefly ring at a pitch.
//    • phone video    — speech + a music bed through a tiny speaker that drops
//                     the bass fundamentals but keeps their overtones.
//
//  Everything is generated from a seed, so a clip is identical on every run
//  and benchmark results only move when the TRACKER changes.
//

import Foundation
// `PitchBench/run.sh` compiles this file straight into a Mac command-line
// tool alongside the app's pitch sources, where there's no module to import.
#if !PITCH_BENCH_CLI
@testable import GuitarKit
#endif

enum Interference: String, CaseIterable {
    case quietRoom = "quiet room"
    case rumble = "rumble + hum"
    case fan
    case otherGuitar = "other guitar"
    case keyboard = "keyboard chords"
    case speech
    case clicks = "clicks + knocks"
    case phoneVideo = "phone video"

    /// The levels each kind is tested at, as RMS over the clip in dBFS:
    /// below a soft pluck, and at/above it.
    static let levelsDBFS: [Double] = [-55, -40]

    /// The faint broadband hiss present in EVERY clip (≈ −72 dBFS) — the
    /// "quiet room" condition is this and nothing else.
    static let roomHissRMS: Float = 0.00025

    /// Render `count` samples of this interference at `levelDBFS` RMS.
    /// `avoidingHz` keeps pitched interferers (another guitar) at least a
    /// semitone away from the string under test, so "a reading of the
    /// interferer" and "a correct reading" can't be confused when scoring.
    func render(count: Int, sampleRate: Double, levelDBFS: Double,
                seed: UInt64, avoidingHz: Double? = nil) -> [Float] {
        var rng = SeededRandom(seed: seed)
        let raw: [Float]
        switch self {
        case .quietRoom:   return [Float](repeating: 0, count: count)
        case .rumble:      raw = Self.rumble(count, sampleRate, &rng)
        case .fan:         raw = Self.fan(count, sampleRate, &rng)
        case .otherGuitar: raw = Self.otherGuitar(count, sampleRate, &rng, avoidingHz: avoidingHz)
        case .keyboard:    raw = Self.keyboard(count, sampleRate, &rng)
        case .speech:      raw = Self.speech(count, sampleRate, &rng)
        case .clicks:      raw = Self.clicks(count, sampleRate, &rng)
        case .phoneVideo:  raw = Self.phoneVideo(count, sampleRate, &rng)
        }
        return Self.normalized(raw, rms: Float(pow(10, levelDBFS / 20)))
    }

    // MARK: Steady noise

    /// Low-frequency room rumble (brown noise: random, energy piled into the
    /// lows — traffic, building HVAC) plus 60 Hz mains hum.
    private static func rumble(_ n: Int, _ sr: Double, _ rng: inout SeededRandom) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        var y: Float = 0
        for i in 0..<n {
            y = 0.997 * y + rng.gaussian()       // leaky integrator → brown noise
            out[i] = y
        }
        out = normalized(out, rms: 1)
        let hum = Signal.hum(frequency: 60, amplitude: 0.5, sampleRate: sr, count: n)
        for i in 0..<n { out[i] += hum[i] }
        return out
    }

    /// Fan / AC: broadband hiss, softened above 4 kHz.
    private static func fan(_ n: Int, _ sr: Double, _ rng: inout SeededRandom) -> [Float] {
        var lp = Biquad.lowPass(cutoffHz: 4_000, sampleRate: sr)
        return (0..<n).map { _ in lp.process(rng.gaussian()) }
    }

    // MARK: Other instruments

    /// Someone else plucking random notes on a guitar every ~0.5–1.1 s.
    private static func otherGuitar(_ n: Int, _ sr: Double, _ rng: inout SeededRandom,
                                    avoidingHz: Double?) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        let avoid = avoidingHz.map { 69 + 12 * log2($0 / 440) }
        var t = rng.range(0.0...0.3)
        while t < Double(n) / sr {
            var midi: Double
            repeat { midi = Double(Int(rng.range(40...76))) }   // E2…E5
            while avoid.map({ abs(midi - $0) <= 1.5 }) ?? false
            let note = Signal.pluckedGuitarNote(fundamental: 440 * pow(2, (midi - 69) / 12),
                                                sampleRate: sr, count: Int(1.5 * sr), decayTime: 0.7)
            add(note, into: &out, at: Int(t * sr), gain: Float(rng.range(0.5...1)))
            t += rng.range(0.5...1.1)
        }
        return out
    }

    /// A keyboard playing a new triad every 1.5 s (piano-like decaying partials).
    private static func keyboard(_ n: Int, _ sr: Double, _ rng: inout SeededRandom) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        var t = rng.range(0.0...0.5)
        while t < Double(n) / sr {
            let root = Double(Int(rng.range(48...67)))          // C3…G4
            let third = rng.unit() < 0.5 ? 3.0 : 4.0            // minor / major
            for interval in [0, third, 7] {
                let f0 = 440 * pow(2, (root + interval - 69) / 12)
                addPartials(into: &out, at: Int(t * sr), sampleRate: sr, f0: { _ in f0 },
                            amplitudes: [1, 0.5, 0.33, 0.25, 0.2, 0.12],
                            length: Int(1.5 * sr), decay: 1.2)
            }
            t += 1.5
        }
        return out
    }

    // MARK: Speech

    /// Vowel formants (F1, F2) in Hz: "ah", "ee", "oo", "eh", "uh".
    private static let vowels: [(Double, Double)] = [(730, 1090), (270, 2290), (300, 870),
                                                     (530, 1840), (640, 1190)]

    /// Synthetic talking: voiced syllables (a harmonic glottal source whose
    /// pitch GLIDES, shaped by vowel formants), unvoiced "s"/"f" bursts, and
    /// gaps between words — the rhythm and pitch range of real speech.
    private static func speech(_ n: Int, _ sr: Double, _ rng: inout SeededRandom) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        let speakerPitch = rng.range(95...210)                 // low male … high female
        var hp = Biquad.highPass(cutoffHz: 3_000, sampleRate: sr)
        var t = rng.range(0.0...0.2)
        var syllable = 0
        while t < Double(n) / sr {
            // VOICED syllable: pitch glides ±15% around a drifting centre.
            let length = Int(rng.range(0.12...0.30) * sr)
            let start = speakerPitch * rng.range(0.85...1.25)
            let glide = rng.range(-0.15...0.15)
            let (f1, f2) = vowels[Int(rng.range(0...Double(vowels.count - 1)))]
            // Harmonic k's loudness: a 1/k glottal source × the formant peaks.
            let harmonics = Int(4_000 / start)
            let amplitudes: [Float] = (1...max(harmonics, 1)).map { k in
                let f = Double(k) * start
                let formant = [(f1, 90.0), (f2, 120.0), (2_500, 160.0)]
                    .map { 1 / (1 + pow((f - $0.0) / $0.1, 2)) }.reduce(0.05, +)
                return Float(formant / Double(k))
            }
            addPartials(into: &out, at: Int(t * sr), sampleRate: sr,
                        f0: { progress in start * (1 + glide * (progress - 0.5) * 2) },
                        amplitudes: amplitudes, length: length, decay: nil)
            t += Double(length) / sr

            // Sometimes an unvoiced consonant ("s", "f"): high-passed noise.
            if rng.unit() < 0.25 {
                let burst = Int(rng.range(0.06...0.12) * sr), at = Int(t * sr)
                for i in 0..<burst where at + i < n {
                    out[at + i] += 0.3 * hann(i, burst) * hp.process(rng.gaussian())
                }
                t += Double(burst) / sr
            }
            // Gaps: short between syllables, longer between phrases.
            syllable += 1
            t += syllable % 6 == 0 ? rng.range(0.3...0.6) : rng.range(0.03...0.15)
        }
        return out
    }

    // MARK: Clicks and knocks

    /// Typing / tapping / setting things down (~4 events per second): plain
    /// clicks, low wooden KNOCKS that ring at a pitch inside the guitar range,
    /// and bright inharmonic CLINKS (glass, metal).
    private static func clicks(_ n: Int, _ sr: Double, _ rng: inout SeededRandom) -> [Float] {
        var out = [Float](repeating: 0, count: n)
        var t = 0.0
        while true {
            t += -log(max(rng.unit(), 1e-9)) / 4          // random gaps, 4/s on average
            let at = Int(t * sr)
            guard at < n else { break }
            let gain = Float(rng.range(0.3...1))
            let kind = rng.unit()
            if kind < 0.5 {                                // click: 2 ms noise burst
                for i in 0..<Int(0.002 * sr) where at + i < n {
                    out[at + i] += gain * rng.gaussian() * Float(exp(-Double(i) / (0.0007 * sr)))
                }
            } else if kind < 0.8 {                         // knock: rings 120–400 Hz
                let f = rng.range(120...400)
                addPartials(into: &out, at: at, sampleRate: sr, f0: { _ in f },
                            amplitudes: [gain, gain * 0.3], length: Int(0.12 * sr), decay: 0.025)
            } else {                                       // clink: inharmonic, bright
                let f = rng.range(1_500...4_000)
                for ratio in [1.0, 2.76, 5.4] {
                    addPartials(into: &out, at: at, sampleRate: sr, f0: { _ in f * ratio },
                                amplitudes: [gain * 0.5], length: Int(0.3 * sr), decay: 0.08)
                }
            }
        }
        return out
    }

    // MARK: Phone video

    /// A TikTok-style clip from a phone speaker: speech over a music bed (kick,
    /// snare, a bass line and chords at ~100 BPM). The tiny speaker removes
    /// everything below ~300 Hz — so the bass line's FUNDAMENTALS vanish while
    /// their overtones remain.
    private static func phoneVideo(_ n: Int, _ sr: Double, _ rng: inout SeededRandom) -> [Float] {
        var out = normalized(speech(n, sr, &rng), rms: 1)
        var bed = [Float](repeating: 0, count: n)
        let beat = 0.6
        var b = 0
        while Double(b) * beat < Double(n) / sr {
            let at = Int(Double(b) * beat * sr)
            // Kick: a falling sine "thump".
            var phase = 0.0
            for i in 0..<Int(0.25 * sr) where at + i < n {
                let time = Double(i) / sr
                phase += 2 * .pi * (50 + 70 * exp(-time / 0.03)) / sr
                bed[at + i] += Float(sin(phase) * exp(-time / 0.15))
            }
            // Snare on beats 2 and 4: a noise burst.
            if b % 2 == 1 {
                for i in 0..<Int(0.15 * sr) where at + i < n {
                    bed[at + i] += 0.5 * rng.gaussian() * Float(exp(-Double(i) / (0.05 * sr)))
                }
            }
            // Bass line: a low note per beat (41–82 Hz).
            let bass = 41.2 * pow(2, Double(Int(rng.range(0...12))) / 12)
            addPartials(into: &bed, at: at, sampleRate: sr, f0: { _ in bass },
                        amplitudes: [1, 0.6, 0.4, 0.25, 0.15], length: Int(beat * sr), decay: 0.4)
            b += 1
        }
        let chords = keyboard(n, sr, &rng)
        for i in 0..<n { bed[i] += 0.3 * chords[i] }
        bed = normalized(bed, rms: 0.6)
        for i in 0..<n { out[i] += bed[i] }

        // The phone speaker: no bass, no extreme highs.
        var hp1 = Biquad.highPass(cutoffHz: 300, sampleRate: sr)
        var hp2 = Biquad.highPass(cutoffHz: 300, sampleRate: sr)
        var lp = Biquad.lowPass(cutoffHz: 7_000, sampleRate: sr)
        return out.map { lp.process(hp2.process(hp1.process($0))) }
    }

    // MARK: Helpers

    /// Additive synthesis: harmonics k·f0 (amplitude `amplitudes[k-1]`) for
    /// `length` samples starting at `offset`. `f0` takes progress 0…1 so the
    /// pitch can glide; `decay` is an exponential time constant (seconds), or
    /// `nil` for a smooth Hann swell (speech syllables).
    private static func addPartials(into out: inout [Float], at offset: Int, sampleRate sr: Double,
                                    f0: (Double) -> Double, amplitudes: [Float],
                                    length: Int, decay: Double?) {
        var phases = [Double](repeating: 0, count: amplitudes.count)
        let attack = Int(0.004 * sr)                 // 4 ms fade-in: no click at the start
        for i in 0..<length where offset + i < out.count {
            let fundamental = f0(Double(i) / Double(length))
            var envelope: Float
            if let decay {
                envelope = Float(exp(-Double(i) / (decay * sr)))
                if i < attack { envelope *= Float(i) / Float(attack) }
            } else {
                envelope = hann(i, length)
            }
            var sample: Float = 0
            for k in amplitudes.indices {
                let f = fundamental * Double(k + 1)
                guard f < sr / 2 else { break }
                phases[k] += 2 * .pi * f / sr
                sample += amplitudes[k] * Float(sin(phases[k]))
            }
            out[offset + i] += envelope * sample
        }
    }

    private static func add(_ signal: [Float], into out: inout [Float], at offset: Int, gain: Float) {
        for i in signal.indices where offset + i < out.count { out[offset + i] += gain * signal[i] }
    }

    private static func hann(_ i: Int, _ length: Int) -> Float {
        Float(0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(max(length - 1, 1))))
    }

    /// Scale a signal to an exact RMS.
    static func normalized(_ signal: [Float], rms: Float) -> [Float] {
        let current = AudioLevel.rms(of: signal)
        guard current > 0 else { return signal }
        return signal.map { $0 * rms / current }
    }
}

/// A tiny deterministic random generator (same seed → same sequence), so
/// generated clips are identical on every run.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    /// Uniform in 0..<1.
    mutating func unit() -> Double {
        state = 6_364_136_223_846_793_005 &* state &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }

    mutating func range(_ r: ClosedRange<Double>) -> Double {
        r.lowerBound + unit() * (r.upperBound - r.lowerBound)
    }

    /// Zero-mean, unit-variance, roughly Gaussian (sum of 4 uniforms).
    mutating func gaussian() -> Float {
        let sum = (0..<4).reduce(0.0) { acc, _ in acc + unit() * 2 - 1 }
        return Float(sum / (4.0 / 3.0).squareRoot())
    }
}
