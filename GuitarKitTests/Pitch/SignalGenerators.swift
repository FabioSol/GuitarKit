//
//  SignalGenerators.swift
//  GuitarKitTests
//
//  Test fixtures: deterministic synthetic audio so pitch detection can be
//  verified WITHOUT a microphone. We know the exact frequency we generated, so
//  we can assert the detector recovers it. Everything here is pure and seeded —
//  no randomness that would make tests flaky.
//

import Foundation

/// A namespace of signal builders for tests.
enum Signal {

    /// A pure sine wave of `frequency` Hz.
    ///
    /// THE MATH: sample i is `amplitude · sin(2π · frequency · i / sampleRate)`.
    /// `2π · frequency / sampleRate` is the phase advance per sample.
    static func sine(
        frequency: Double,
        sampleRate: Double = 44_100,
        count: Int = 4_096,
        amplitude: Float = 0.8
    ) -> [Float] {
        let phaseStep = 2.0 * Double.pi * frequency / sampleRate
        return (0..<count).map { i in
            amplitude * Float(sin(phaseStep * Double(i)))
        }
    }

    /// A harmonically rich tone: a fundamental plus overtones at 2×, 3×, …,
    /// each with its own amplitude. Used to test octave-error resistance — we
    /// deliberately make a *harmonic* louder than the fundamental and check the
    /// detector still reports the fundamental.
    ///
    /// - Parameter harmonicAmplitudes: amplitude of harmonic n is element n
    ///   (index 0 = the fundamental, index 1 = the 2nd harmonic, …).
    static func harmonicTone(
        fundamental: Double,
        harmonicAmplitudes: [Float],
        sampleRate: Double = 44_100,
        count: Int = 4_096
    ) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for (index, amp) in harmonicAmplitudes.enumerated() where amp != 0 {
            let harmonicFreq = fundamental * Double(index + 1)
            let phaseStep = 2.0 * Double.pi * harmonicFreq / sampleRate
            for i in 0..<count {
                out[i] += amp * Float(sin(phaseStep * Double(i)))
            }
        }
        return out
    }

    /// Deterministic pseudo-random white noise via a small linear congruential
    /// generator (LCG). Seeded, so the "noise" is identical every test run —
    /// giving us a stable input to assert "noise is gated, not pitched".
    static func noise(count: Int = 4_096, amplitude: Float = 0.5, seed: UInt64 = 1) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            // Numerical Recipes LCG constants; we only need cheap, repeatable bits.
            state = 6_364_136_223_846_793_005 &* state &+ 1_442_695_040_888_963_407
            // Map the top bits to roughly −1…+1, then scale.
            let unit = Float(state >> 33) / Float(UInt32.max) * 2 - 1
            return amplitude * unit
        }
    }

    // MARK: - Realistic guitar fixtures
    //
    // The builders above make IDEAL signals (pure/exactly-harmonic sines). A real
    // plucked string is messier in ways that specifically trip up pitch detectors,
    // and those messy cases are exactly the "flaky low string" complaints. The
    // builders below model the four real-world gremlins so tests can prove the
    // detection pipeline survives them:
    //   • a WEAK fundamental (overtones louder than the root → octave errors),
    //   • INHARMONICITY (stiff strings push overtones sharp of exact multiples),
    //   • DECAY (a pluck fades, so the tail is quieter + less periodic), and
    //   • mains HUM (50/60 Hz buzz sitting under a low note).
    // They compose (via `mix`/`decaying`) so a test can stack several at once.

    /// Add several equal-length signals sample-by-sample (a mix bus). Used to drop
    /// a tone INTO hum/noise. Shorter inputs are treated as silence past their end,
    /// so mismatched lengths still combine safely.
    static func mix(_ signals: [Float]...) -> [Float] {
        let count = signals.map(\.count).max() ?? 0
        var out = [Float](repeating: 0, count: count)
        for signal in signals {
            for i in signal.indices { out[i] += signal[i] }
        }
        return out
    }

    /// Apply an exponentially-decaying envelope to a signal — the shape of a
    /// plucked note: loud attack, fading tail. `decayTime` is the time-constant in
    /// seconds (amplitude falls to 1/e ≈ 37% after that long). Shorter `decayTime`
    /// = a faster-dying note, which stresses detection on the quiet, less-periodic
    /// tail.
    static func decaying(
        _ samples: [Float],
        decayTime: Double,
        sampleRate: Double = 44_100
    ) -> [Float] {
        guard decayTime > 0 else { return samples }
        return samples.enumerated().map { i, x in
            let t = Double(i) / sampleRate
            return x * Float(exp(-t / decayTime))
        }
    }

    /// 50/60 Hz mains HUM: the fundamental plus a couple of its harmonics, the
    /// low-frequency buzz a single-coil pickup or a noisy room adds under a quiet
    /// low note. Sits BELOW a guitar's low E (82 Hz), so the band-pass preprocessor
    /// is meant to remove it — these fixtures prove it does.
    static func hum(
        frequency: Double = 60,
        amplitude: Float = 0.3,
        sampleRate: Double = 44_100,
        count: Int = 4_096
    ) -> [Float] {
        harmonicTone(
            fundamental: frequency,
            harmonicAmplitudes: [amplitude, amplitude * 0.4, amplitude * 0.2],
            sampleRate: sampleRate,
            count: count
        )
    }

    /// An INHARMONIC plucked-string tone: like `harmonicTone`, but each overtone is
    /// stretched SHARP of an exact multiple, because a real string has stiffness.
    /// Partial n sits at `n · f · √(1 + B·n²)` (the standard stiff-string model);
    /// `inharmonicity` is B — ~0.0001–0.0005 for steel guitar strings. The detector
    /// must still report the fundamental `f`, not get dragged up by the sharp
    /// partials.
    ///
    /// - Parameter harmonicAmplitudes: amplitude of partial n is element n
    ///   (index 0 = the fundamental, index 1 = the 2nd partial, …).
    static func inharmonicTone(
        fundamental: Double,
        harmonicAmplitudes: [Float],
        inharmonicity B: Double = 0.0003,
        sampleRate: Double = 44_100,
        count: Int = 4_096
    ) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for (index, amp) in harmonicAmplitudes.enumerated() where amp != 0 {
            let n = Double(index + 1)
            // Stiffness pushes partial n sharp by √(1 + B·n²).
            let partialFreq = n * fundamental * (1 + B * n * n).squareRoot()
            let phaseStep = 2.0 * Double.pi * partialFreq / sampleRate
            for i in 0..<count {
                out[i] += amp * Float(sin(phaseStep * Double(i)))
            }
        }
        return out
    }

    /// A realistic plucked-guitar note in ONE call: a harmonically-rich tone with a
    /// deliberately WEAK fundamental (the body/pickup emphasise the mids, so the
    /// 2nd/3rd partials are louder than the root — the classic octave-error trap),
    /// gentle string stiffness, and a decaying envelope. This is the everyday "hard
    /// case" a guitar tuner faces, bundled so tests read clearly.
    static func pluckedGuitarNote(
        fundamental: Double,
        sampleRate: Double = 44_100,
        count: Int = 4_096,
        decayTime: Double = 0.6,
        inharmonicity B: Double = 0.0003
    ) -> [Float] {
        // A weak root under louder low harmonics, tapering off up the series — the
        // measured shape of a plucked low string.
        let partials: [Float] = [0.25, 1.0, 0.8, 0.5, 0.3, 0.2, 0.12]
        let tone = inharmonicTone(
            fundamental: fundamental,
            harmonicAmplitudes: partials,
            inharmonicity: B,
            sampleRate: sampleRate,
            count: count
        )
        return decaying(tone, decayTime: decayTime, sampleRate: sampleRate)
    }
}
