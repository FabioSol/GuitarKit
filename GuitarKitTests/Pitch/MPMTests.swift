//
//  MPMTests.swift
//  GuitarKitTests
//
//  Behavioral tests for the pure McLeod Pitch Method core. We feed synthetic
//  signals whose exact frequency we control and assert the detector recovers it
//  — including the hard cases a real tuner faces: low bass and harmonic-rich
//  tones that fool naive detectors into octave errors.
//

import XCTest
@testable import GuitarKit

final class MPMTests: XCTestCase {

    private let sampleRate = 44_100.0

    /// Assert a detected frequency is within `cents` of the expected value.
    /// We measure tolerance in *cents* (not Hz) because that's the musically
    /// meaningful unit and it scales correctly across the range.
    private func assertFrequency(
        _ estimate: MPM.Estimate?,
        near expected: Double,
        withinCents cents: Double = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let estimate else {
            return XCTFail("expected a pitch near \(expected) Hz, got nil", file: file, line: line)
        }
        let off = abs(PitchCalculator.cents(from: Double(estimate.frequency), to: expected))
        XCTAssertLessThanOrEqual(
            off, cents,
            "\(estimate.frequency) Hz is \(off) cents from \(expected) Hz",
            file: file, line: line
        )
    }

    // MARK: - Sustained tones across the range

    func test_detects_concertA_440() {
        let s = Signal.sine(frequency: 440, sampleRate: sampleRate)
        assertFrequency(MPM.detectPitch(samples: s, sampleRate: sampleRate), near: 440)
    }

    func test_detects_guitarLowE_82() {
        // E2 = 82.41 Hz, a guitar's lowest open string.
        let s = Signal.sine(frequency: 82.41, sampleRate: sampleRate)
        assertFrequency(MPM.detectPitch(samples: s, sampleRate: sampleRate), near: 82.41)
    }

    func test_detects_A2_110() {
        let s = Signal.sine(frequency: 110, sampleRate: sampleRate)
        assertFrequency(MPM.detectPitch(samples: s, sampleRate: sampleRate), near: 110)
    }

    func test_detects_highTone_880() {
        let s = Signal.sine(frequency: 880, sampleRate: sampleRate)
        assertFrequency(MPM.detectPitch(samples: s, sampleRate: sampleRate), near: 880)
    }

    // MARK: - Low bass needs a longer window

    func test_detects_bassLowB_with_longer_window() {
        // ~41 Hz (a 5-string bass low B). At 44.1 kHz this fits only ~10 periods
        // in 4096 samples — too few. With a longer 8192-sample window the period
        // is comfortably resolvable, which is exactly the PRD's "longer windows
        // for low bass" requirement.
        let s = Signal.sine(frequency: 41.20, sampleRate: sampleRate, count: 8_192)
        assertFrequency(
            MPM.detectPitch(samples: s, sampleRate: sampleRate),
            near: 41.20, withinCents: 10
        )
    }

    // MARK: - Boundary: a hump cresting on the final lag (audit P2)

    func test_lowNote_whosePeriodReachesBufferEnd_isStillDetected() {
        // A 50 Hz tone has a period of exactly 882 samples at 44.1 kHz. Setting the
        // search FLOOR to 50 Hz puts `maxLag` right ON that period, so the NSDF's
        // fundamental hump crests at the very LAST lag. The old `keyMaxima` walk
        // ran `while i < maxLag` and required an INTERIOR local maximum, so on this
        // monotonically-rising final hump it recorded nothing and `detectPitch`
        // returned nil. The boundary-inclusive argmax walk captures the crest.
        let s = Signal.sine(frequency: 50, sampleRate: sampleRate, count: 4_096)
        let estimate = MPM.detectPitch(
            samples: s, sampleRate: sampleRate,
            minFrequency: 50, maxFrequency: 1500
        )
        assertFrequency(estimate, near: 50, withinCents: 10)
    }

    // MARK: - Octave-error resistance

    func test_octaveAmbiguous_reportsFundamental_notHarmonic() {
        // A 110 Hz tone whose 2nd harmonic (220 Hz) is the LOUDEST partial. A
        // naive "tallest FFT bin" detector would report 220 Hz (an octave high).
        // MPM's first-tall-peak rule should still report ~110 Hz.
        let s = Signal.harmonicTone(
            fundamental: 110,
            harmonicAmplitudes: [0.4, 1.0, 0.7, 0.3]
        )
        assertFrequency(MPM.detectPitch(samples: s, sampleRate: sampleRate), near: 110, withinCents: 8)
    }

    // MARK: - Gating: silence & noise produce no pitch

    func test_silence_returnsNil() {
        let silence = [Float](repeating: 0, count: 4_096)
        XCTAssertNil(MPM.detectPitch(samples: silence, sampleRate: sampleRate))
    }

    func test_whiteNoise_isNotConfidentlyPitched() {
        // Broadband noise has no strong periodicity, so its best NSDF peak should
        // fall below the clarity gate → nil.
        let n = Signal.noise(count: 4_096, amplitude: 0.5, seed: 42)
        XCTAssertNil(MPM.detectPitch(samples: n, sampleRate: sampleRate))
    }

    // MARK: - Clarity score

    func test_pureTone_hasHighClarity() {
        let s = Signal.sine(frequency: 196, sampleRate: sampleRate) // G3
        let estimate = MPM.detectPitch(samples: s, sampleRate: sampleRate)
        XCTAssertNotNil(estimate)
        // A clean sustained sine should be very nearly perfectly periodic.
        XCTAssertGreaterThan(estimate?.clarity ?? 0, 0.95)
    }
}
