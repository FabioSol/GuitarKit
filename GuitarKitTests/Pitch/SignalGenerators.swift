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
}
