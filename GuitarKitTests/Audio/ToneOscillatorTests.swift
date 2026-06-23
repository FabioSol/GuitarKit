//
//  ToneOscillatorTests.swift
//  GuitarKitTests
//
//  Behavioral tests for the PURE tone-synthesis math. Everything here is
//  deterministic Float-in/Float-out — no audio hardware, no AVFoundation. We
//  deliberately do NOT test `ToneGenerator` or `AudioSessionCoordinator`: those
//  drive real speakers/hardware and can't be asserted on in a unit test. We test
//  exactly the part the PRD says we can — the oscillator — for the four
//  properties that matter: no clipping, non-silence, safe edge cases, and the
//  right pitch (period).
//

import XCTest
@testable import GuitarKit

final class ToneOscillatorTests: XCTestCase {

    // A standard sample rate to synth against in tests.
    private let sampleRate: Double = 44_100

    // MARK: - No clipping (output stays within -1...1)

    func test_samples_neverExceedFullScale() {
        // Synthesize a couple of cycles of a typical guitar pitch (A2 ≈ 110 Hz)
        // and assert EVERY sample is within the legal digital-audio range. If the
        // harmonic sum weren't normalized this would fail (it'd clip past 1.0).
        let tone = ToneOscillator.samples(count: 4096, frequencyHz: 110, sampleRate: sampleRate)
        for sample in tone {
            XCTAssertGreaterThanOrEqual(sample, -1.0)
            XCTAssertLessThanOrEqual(sample, 1.0)
        }
    }

    func test_singleSample_atAnyPhase_isWithinUnitRange() {
        // Sweep the phase across several full turns; the waveform value must
        // never escape -1...1 at any angle.
        for step in stride(from: Float(0), through: Float.pi * 8, by: 0.05) {
            let value = ToneOscillator.sample(atPhase: step)
            XCTAssertGreaterThanOrEqual(value, -1.0)
            XCTAssertLessThanOrEqual(value, 1.0)
        }
    }

    // MARK: - Non-silence (a real tone has energy)

    func test_samples_ofARealTone_areNonSilent() {
        // A genuine tone should carry energy — its RMS must be clearly above
        // zero. We reuse `AudioLevel.rms` (already trusted) as the measure.
        let tone = ToneOscillator.samples(count: 4096, frequencyHz: 220, sampleRate: sampleRate)
        XCTAssertGreaterThan(AudioLevel.rms(of: tone), 0.1)
    }

    func test_samples_swingBothPositiveAndNegative() {
        // A real oscillation crosses zero in both directions — assert the buffer
        // contains both a clearly positive and a clearly negative sample (i.e.
        // it isn't stuck at a constant offset).
        let tone = ToneOscillator.samples(count: 2048, frequencyHz: 196, sampleRate: sampleRate)
        XCTAssertTrue(tone.contains { $0 > 0.1 }, "expected some positive swing")
        XCTAssertTrue(tone.contains { $0 < -0.1 }, "expected some negative swing")
    }

    // MARK: - Edge cases (silence / zero length handled, no crash)

    func test_samples_zeroLength_isEmpty() {
        XCTAssertTrue(ToneOscillator.samples(count: 0, frequencyHz: 440, sampleRate: sampleRate).isEmpty)
    }

    func test_samples_negativeLength_isEmpty() {
        XCTAssertTrue(ToneOscillator.samples(count: -10, frequencyHz: 440, sampleRate: sampleRate).isEmpty)
    }

    func test_samples_zeroFrequency_isSilent() {
        // A 0 Hz "pitch" doesn't advance the phase, so every sample is sin(0) = 0
        // — a flat, silent (all-zero) buffer rather than a crash.
        let tone = ToneOscillator.samples(count: 512, frequencyHz: 0, sampleRate: sampleRate)
        XCTAssertEqual(tone.count, 512)
        XCTAssertEqual(AudioLevel.rms(of: tone), 0, accuracy: 0.0001)
    }

    func test_phaseStep_withZeroSampleRate_isZero_andDoesNotCrash() {
        // A degenerate sample rate must not divide by zero; it yields a 0 step.
        XCTAssertEqual(ToneOscillator.phaseStep(frequencyHz: 440, sampleRate: 0), 0, accuracy: 0.0001)
    }

    // MARK: - Pitch correctness (the phase step maps to the right period)

    func test_phaseStep_matchesTwoPiOverPeriod() {
        // The phase step is 2π · f / sr. Equivalently, after `sr / f` samples
        // (= the period in samples) the phase should have advanced exactly one
        // full turn (2π). We verify the formula directly.
        let frequency = 440.0
        let step = ToneOscillator.phaseStep(frequencyHz: frequency, sampleRate: sampleRate)
        let expected = Float(2.0 * Double.pi * frequency / sampleRate)
        XCTAssertEqual(step, expected, accuracy: 0.0001)

        // And the implied period (samples per cycle) matches sr / f.
        let periodSamples = (Float.pi * 2) / step
        XCTAssertEqual(periodSamples, Float(sampleRate / frequency), accuracy: 0.01)
    }

    func test_higherFrequency_hasShorterPeriod() {
        // A higher pitch must take a bigger phase step (fewer samples per cycle).
        let low  = ToneOscillator.phaseStep(frequencyHz: 110, sampleRate: sampleRate)
        let high = ToneOscillator.phaseStep(frequencyHz: 880, sampleRate: sampleRate)
        XCTAssertLessThan(low, high)
    }

    func test_dominantPeriod_matchesRequestedFrequency_viaZeroCrossings() {
        // INDEPENDENT pitch check: count how many times the FUNDAMENTAL completes
        // a cycle by counting upward zero-crossings (negative→positive). Over a
        // known duration, cycles ≈ frequency · seconds.
        //
        // To make the fundamental's crossings unambiguous we measure a pure
        // sine (one harmonic) rather than the full timbre — overtones add extra
        // zero-crossings within a cycle. The phase math under test is identical;
        // we're validating the period, which the harmonics don't change.
        let frequency = 100.0          // a tidy round number
        let duration = 1.0             // one second
        let count = Int(sampleRate * duration)

        // Build a single-harmonic sine using the same phase step under test.
        let step = ToneOscillator.phaseStep(frequencyHz: frequency, sampleRate: sampleRate)
        var phase: Float = 0
        var previous: Float = 0
        var upwardCrossings = 0
        let twoPi = Float.pi * 2

        for i in 0..<count {
            let value = sin(phase)
            // Count a crossing when we pass from <0 up through 0.
            if i > 0, previous < 0, value >= 0 { upwardCrossings += 1 }
            previous = value
            phase += step
            if phase >= twoPi { phase -= twoPi }
        }

        // ~100 cycles in one second. Allow ±1 for the boundary sample.
        XCTAssertEqual(Double(upwardCrossings), frequency, accuracy: 1.0)
    }

    // MARK: - Generator (the real-time phase walker) stays continuous & bounded

    func test_generator_producesBoundedNonSilentSamples() {
        var gen = ToneOscillator.Generator(frequencyHz: 146.83, sampleRate: sampleRate)  // D3
        var produced = [Float]()
        for _ in 0..<2048 { produced.append(gen.nextSample()) }

        for sample in produced {
            XCTAssertGreaterThanOrEqual(sample, -1.0)
            XCTAssertLessThanOrEqual(sample, 1.0)
        }
        XCTAssertGreaterThan(AudioLevel.rms(of: produced), 0.1)
    }

    func test_generator_matchesBufferSynthesis_forSamePitch() {
        // The Generator and the buffer helper share the same math, both starting
        // at phase 0, so they must produce identical samples for the same pitch.
        let frequency = 261.63   // C4
        let buffer = ToneOscillator.samples(count: 256, frequencyHz: frequency, sampleRate: sampleRate)

        var gen = ToneOscillator.Generator(frequencyHz: frequency, sampleRate: sampleRate)
        for i in 0..<256 {
            XCTAssertEqual(gen.nextSample(), buffer[i], accuracy: 0.0001)
        }
    }

    func test_generator_retune_changesPhaseStep() {
        // Retuning to a higher pitch should increase the phase step (so it'll
        // sweep through cycles faster), without us resetting anything.
        var gen = ToneOscillator.Generator(frequencyHz: 110, sampleRate: sampleRate)
        let lowStep = gen.phaseStep
        gen.setFrequency(220, sampleRate: sampleRate)
        XCTAssertGreaterThan(gen.phaseStep, lowStep)
    }
}
