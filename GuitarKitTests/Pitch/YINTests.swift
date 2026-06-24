//
//  YINTests.swift
//  GuitarKitTests
//
//  Behavioral tests for the pure YIN detector — the same battery the MPM core
//  faces: sustained tones across the range, octave resistance on harmonic-rich
//  signals, and rejection of noise/silence. Synthetic inputs (known frequency)
//  let us assert YIN recovers the pitch without a microphone.
//

import XCTest
@testable import GuitarKit

final class YINTests: XCTestCase {

    private let sampleRate = 44_100.0

    /// Assert a detected frequency is within `cents` of the expected value
    /// (cents = the musically meaningful unit, scaling correctly across the range).
    private func assertFrequency(
        _ estimate: PitchEstimate?,
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
        assertFrequency(YIN.detectPitch(samples: s, sampleRate: sampleRate), near: 440)
    }

    func test_detects_guitarLowE_82() {
        // E2 = 82.41 Hz — a guitar's lowest open string (the case that was flaky).
        let s = Signal.sine(frequency: 82.41, sampleRate: sampleRate)
        assertFrequency(YIN.detectPitch(samples: s, sampleRate: sampleRate), near: 82.41)
    }

    func test_detects_bassLowB_31() {
        // B0 ≈ 30.87 Hz — a 5-string bass's lowest string, near the search floor.
        let s = Signal.sine(frequency: 30.87, sampleRate: sampleRate, count: 8_192)
        assertFrequency(YIN.detectPitch(samples: s, sampleRate: sampleRate), near: 30.87, withinCents: 12)
    }

    func test_detects_highTone_880() {
        let s = Signal.sine(frequency: 880, sampleRate: sampleRate)
        assertFrequency(YIN.detectPitch(samples: s, sampleRate: sampleRate), near: 880)
    }

    // MARK: - Octave resistance

    func test_harmonicRichTone_reportsFundamental_notAnOctaveUp() {
        // A fundamental with a LOUDER 2nd harmonic — the classic octave-error trap.
        let s = Signal.harmonicTone(
            fundamental: 110,                       // A2
            harmonicAmplitudes: [0.5, 1.0, 0.4, 0.2]
        )
        assertFrequency(YIN.detectPitch(samples: s, sampleRate: sampleRate), near: 110, withinCents: 8)
    }

    // MARK: - Clarity + gating

    func test_cleanTone_hasHighClarity() {
        let s = Signal.sine(frequency: 220, sampleRate: sampleRate)
        let estimate = YIN.detectPitch(samples: s, sampleRate: sampleRate)
        XCTAssertNotNil(estimate)
        XCTAssertGreaterThan(estimate?.clarity ?? 0, 0.8)
    }

    func test_noise_hasLowClarity() {
        // Broadband noise isn't periodic → its clarity should be well below the
        // detector's gate, so the caller rejects it.
        let n = Signal.noise(count: 4_096, amplitude: 0.5, seed: 42)
        let estimate = YIN.detectPitch(samples: n, sampleRate: sampleRate)
        XCTAssertLessThan(estimate?.clarity ?? 1, 0.6)
    }

    func test_silence_returnsNil() {
        let silence = [Float](repeating: 0, count: 4_096)
        XCTAssertNil(YIN.detectPitch(samples: silence, sampleRate: sampleRate))
    }
}
