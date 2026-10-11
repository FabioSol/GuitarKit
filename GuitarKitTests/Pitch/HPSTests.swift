//
//  HPSTests.swift
//  GuitarKitTests
//
//  The pure Harmonic Product Spectrum detector. HPS is the FREQUENCY-domain member
//  of the trio, and its whole reason to exist is WEAK-FUNDAMENTAL notes — so we test
//  it on harmonic-rich tones (what a real instrument makes), the case it shines on.
//  We also pin its KNOWN LIMITATION honestly: a pure sine (no harmonics to multiply)
//  is NOT something HPS can resolve, which is exactly why it rides as an ensemble
//  tie-breaker rather than a standalone default.
//

import XCTest
@testable import GuitarKit

final class HPSTests: XCTestCase {

    private let sampleRate = 44_100.0

    private func assertFrequency(
        _ estimate: PitchEstimate?,
        near expected: Double,
        withinCents tolerance: Double = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let estimate else {
            return XCTFail("expected a pitch near \(expected) Hz, got nil", file: file, line: line)
        }
        let off = abs(PitchCalculator.cents(from: Double(estimate.frequency), to: expected))
        XCTAssertLessThanOrEqual(off, tolerance,
            "\(estimate.frequency) Hz is \(off)¢ from \(expected) Hz", file: file, line: line)
    }

    // MARK: - Harmonic-rich tones across the range

    func test_detectsHarmonicConcertA() {
        let s = Signal.harmonicTone(fundamental: 440, harmonicAmplitudes: [1.0, 0.5, 0.3, 0.2],
                                    sampleRate: sampleRate)
        assertFrequency(HPS.detectPitch(samples: s, sampleRate: sampleRate), near: 440)
    }

    func test_detectsHarmonicLowE() {
        let s = Signal.harmonicTone(fundamental: 82.41, harmonicAmplitudes: [0.6, 1.0, 0.7, 0.4],
                                    sampleRate: sampleRate)
        assertFrequency(HPS.detectPitch(samples: s, sampleRate: sampleRate), near: 82.41)
    }

    func test_detectsHarmonicA2() {
        let s = Signal.harmonicTone(fundamental: 110, harmonicAmplitudes: [0.5, 1.0, 0.6, 0.3],
                                    sampleRate: sampleRate)
        assertFrequency(HPS.detectPitch(samples: s, sampleRate: sampleRate), near: 110)
    }

    // MARK: - The motivation: weak fundamental (the octave trap)

    func test_weakFundamental_reportsTheFundamental_notTheLoudHarmonic() {
        // Root much quieter than the 2nd/3rd partials — where autocorrelation can
        // jump an octave. HPS, requiring agreement across harmonics, holds the root.
        let s = Signal.harmonicTone(fundamental: 82.41,
                                    harmonicAmplitudes: [0.18, 1.0, 0.7, 0.4, 0.25],
                                    sampleRate: sampleRate)
        assertFrequency(HPS.detectPitch(samples: s, sampleRate: sampleRate), near: 82.41)
    }

    func test_pluckedGuitarNote_resolves() {
        assertFrequency(HPS.detectPitch(samples: Signal.pluckedGuitarNote(fundamental: 110),
                                        sampleRate: sampleRate), near: 110, withinCents: 10)
    }

    // MARK: - Clarity / gating

    func test_cleanHarmonicTone_hasHighClarity() {
        let s = Signal.harmonicTone(fundamental: 196, harmonicAmplitudes: [1.0, 0.6, 0.4, 0.2],
                                    sampleRate: sampleRate)
        let estimate = HPS.detectPitch(samples: s, sampleRate: sampleRate)
        XCTAssertNotNil(estimate)
        XCTAssertGreaterThan(estimate?.clarity ?? 0, 0.6,
            "a clean harmonic tone should clear the clarity gate")
    }

    func test_noise_hasLowClarity() {
        let n = Signal.noise(count: 4_096, amplitude: 0.5, seed: 42)
        let estimate = HPS.detectPitch(samples: n, sampleRate: sampleRate)
        XCTAssertLessThan(estimate?.clarity ?? 1, 0.6, "broadband noise should not look tonal")
    }

    func test_silence_returnsNil() {
        XCTAssertNil(HPS.detectPitch(samples: [Float](repeating: 0, count: 4_096),
                                     sampleRate: sampleRate))
    }

    func test_tooFewSamples_returnsNil() {
        // HPS needs a decent window to resolve low pitches; tiny buffers bail out.
        XCTAssertNil(HPS.detectPitch(samples: Signal.sine(frequency: 440, count: 256),
                                     sampleRate: sampleRate))
    }

    // MARK: - Documented limitation: a pure sine is NOT HPS's job

    func test_pureSine_isNotReliablyDetected_byDesign() {
        // A single sine has no harmonic series, so HPS multiplies the lone partial by
        // near-empty bins and locks onto a subharmonic. We don't assert it's correct
        // — we PIN that it doesn't return the true fundamental, documenting WHY HPS
        // is a tie-breaker (where real harmonic content exists) and not a standalone
        // default. If this ever starts returning ~440, HPS gained sine handling and
        // this expectation should be revisited.
        let s = Signal.sine(frequency: 440, sampleRate: sampleRate)
        let estimate = HPS.detectPitch(samples: s, sampleRate: sampleRate)
        let cents = abs(PitchCalculator.cents(from: Double(estimate?.frequency ?? 0), to: 440))
        XCTAssertGreaterThan(cents, 50, "documented: HPS can't resolve a pure (harmonic-free) sine")
    }

    // MARK: - Harmonicity of a GIVEN pitch (the targeted-mode harmonic check)

    func test_harmonicity_pureSine_isHigh() {
        // Unlike detectPitch, checking a KNOWN pitch has no trouble with a sine:
        // all its energy sits on harmonic 1.
        let s = Signal.sine(frequency: 196, sampleRate: sampleRate)
        XCTAssertGreaterThan(HPS.harmonicity(of: 196, in: s, sampleRate: sampleRate) ?? 0, 0.9)
    }

    func test_harmonicity_pluckedString_isHigh() {
        let s = Signal.pluckedGuitarNote(fundamental: 110, sampleRate: sampleRate)
        XCTAssertGreaterThan(HPS.harmonicity(of: 110, in: s, sampleRate: sampleRate) ?? 0, 0.85)
    }

    func test_harmonicity_chord_isLowForEitherNote() {
        // A and D together: half the energy belongs to the OTHER note's series.
        let chord = Signal.mix(
            Signal.harmonicTone(fundamental: 110, harmonicAmplitudes: [1, 0.5, 0.3], sampleRate: sampleRate),
            Signal.harmonicTone(fundamental: 146.83, harmonicAmplitudes: [1, 0.5, 0.3], sampleRate: sampleRate))
        XCTAssertLessThan(HPS.harmonicity(of: 110, in: chord, sampleRate: sampleRate) ?? 1, 0.65)
        XCTAssertLessThan(HPS.harmonicity(of: 146.83, in: chord, sampleRate: sampleRate) ?? 1, 0.65)
    }

    func test_harmonicity_noise_isLow() {
        let noise = PitchBenchmark.gaussianNoise(count: 4_096, rms: 0.1, seed: 4)
        XCTAssertLessThan(HPS.harmonicity(of: 110, in: noise, sampleRate: sampleRate) ?? 1, 0.3)
    }

    func test_harmonicity_silence_isNil() {
        XCTAssertNil(HPS.harmonicity(of: 110, in: [Float](repeating: 0, count: 4_096), sampleRate: sampleRate))
    }
}
