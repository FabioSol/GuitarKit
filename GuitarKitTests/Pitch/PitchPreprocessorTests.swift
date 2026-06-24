//
//  PitchPreprocessorTests.swift
//  GuitarKitTests
//
//  Tests for the band-pass preprocessing stage: the low-pass attenuates highs,
//  the high-pass attenuates lows/hum, the passband survives, and disabling it is
//  a clean pass-through. We measure on the STEADY STATE (after the filter's brief
//  startup transient) so the ratios reflect the real filter response.
//

import XCTest
@testable import GuitarKit

final class PitchPreprocessorTests: XCTestCase {

    private let sampleRate = 44_100.0

    /// Run a pure `freq` sine through a preprocessor and return output/input RMS
    /// measured over the steady-state tail (dropping the first 2048 samples).
    private func gain(freq: Double, highPassHz: Double = 65, lowPassHz: Double = 1000) -> Float {
        var pre = PitchPreprocessor(highPassHz: highPassHz, lowPassHz: lowPassHz, enabled: true)
        let input = Signal.sine(frequency: freq, sampleRate: sampleRate, count: 8_192, amplitude: 0.8)
        let output = pre.process(input, sampleRate: sampleRate)
        let inSS = Array(input[2048...])
        let outSS = Array(output[2048...])
        let inRMS = AudioLevel.rms(of: inSS)
        return inRMS > 0 ? AudioLevel.rms(of: outSS) / inRMS : 0
    }

    // MARK: - Band shape

    func test_passband_survives() {
        // 200 Hz is comfortably inside the 65–1000 Hz band → ~unity gain.
        XCTAssertGreaterThan(gain(freq: 200), 0.7)
    }

    func test_lowPass_attenuatesHighHarmonics() {
        // 5 kHz is well above the 1 kHz low-pass → strongly attenuated.
        XCTAssertLessThan(gain(freq: 5000), 0.15)
    }

    func test_highPass_attenuatesRumble() {
        // 40 Hz is below the 65 Hz high-pass → attenuated (kills rumble/DC/hum).
        XCTAssertLessThan(gain(freq: 40), 0.6)
    }

    func test_guitarLowE_fundamental_passes() {
        // The whole point: a guitar's low E (82 Hz) sits in the band and survives,
        // so detection still sees it.
        XCTAssertGreaterThan(gain(freq: 82.41), 0.6)
    }

    // MARK: - Pass-through when disabled

    func test_disabled_isIdentity() {
        var pre = PitchPreprocessor(enabled: false)
        let input = Signal.sine(frequency: 300, sampleRate: sampleRate, count: 1_024)
        let output = pre.process(input, sampleRate: sampleRate)
        XCTAssertEqual(output, input)
    }

    // MARK: - Doesn't break detection

    func test_preprocessedTone_stillDetectsSamePitch() {
        // A passband tone, filtered, should still resolve to the same frequency
        // (filtering changes amplitude, not the fundamental period).
        var pre = PitchPreprocessor(enabled: true)
        let input = Signal.sine(frequency: 146.83, sampleRate: sampleRate, count: 8_192) // D3
        let filtered = pre.process(input, sampleRate: sampleRate)
        let estimate = YIN.detectPitch(samples: filtered, sampleRate: sampleRate)
        XCTAssertNotNil(estimate)
        let cents = abs(PitchCalculator.cents(from: Double(estimate?.frequency ?? 0), to: 146.83))
        XCTAssertLessThanOrEqual(cents, 6)
    }
}
