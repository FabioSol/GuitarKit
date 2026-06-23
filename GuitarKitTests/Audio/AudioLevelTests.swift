//
//  AudioLevelTests.swift
//  GuitarKitTests
//
//  Behavioral tests for the pure level-metering math (RMS → dBFS → 0...1 →
//  smoothing). All deterministic Double/Float-in, Float-out — no audio hardware.
//

import XCTest
@testable import GuitarKit

final class AudioLevelTests: XCTestCase {

    private let tolerance: Float = 0.0001

    // MARK: - RMS

    func test_rms_ofSilence_isZero() {
        let silence = [Float](repeating: 0, count: 1024)
        XCTAssertEqual(AudioLevel.rms(of: silence), 0, accuracy: tolerance)
    }

    func test_rms_ofEmptyBuffer_isZero_andDoesNotCrash() {
        XCTAssertEqual(AudioLevel.rms(of: []), 0, accuracy: tolerance)
    }

    func test_rms_ofConstantOnes_isOne() {
        // RMS of all-1.0 samples is 1.0 (mean of 1² is 1, sqrt is 1).
        let ones = [Float](repeating: 1, count: 256)
        XCTAssertEqual(AudioLevel.rms(of: ones), 1, accuracy: tolerance)
    }

    func test_rms_isAmplitudeNotAverage_forSymmetricSignal() {
        // A signal that averages to zero (+a, -a, +a, -a) still has real energy.
        // RMS of {+0.5, -0.5} = sqrt((0.25+0.25)/2) = 0.5, not 0.
        let signal: [Float] = [0.5, -0.5, 0.5, -0.5]
        XCTAssertEqual(AudioLevel.rms(of: signal), 0.5, accuracy: tolerance)
    }

    func test_rms_ofFullScaleSquareWave_isOne() {
        // {+1, -1, +1, -1}: every square is 1, mean 1, sqrt 1.
        let square: [Float] = [1, -1, 1, -1, 1, -1]
        XCTAssertEqual(AudioLevel.rms(of: square), 1, accuracy: tolerance)
    }

    // MARK: - meterValue (RMS → 0...1)

    func test_meterValue_ofSilence_isZero() {
        XCTAssertEqual(AudioLevel.meterValue(fromRMS: 0), 0, accuracy: tolerance)
    }

    func test_meterValue_atOrAboveCeiling_isOne() {
        // ceilingDB is -6 dBFS → rms = 10^(-6/20) ≈ 0.501. At/above it, value = 1.
        let ceilingRMS = pow(Float(10), AudioLevel.ceilingDB / 20)
        XCTAssertEqual(AudioLevel.meterValue(fromRMS: ceilingRMS), 1, accuracy: 0.001)
        // A full-scale 1.0 (0 dBFS, above the ceiling) is clamped to 1, not >1.
        XCTAssertEqual(AudioLevel.meterValue(fromRMS: 1.0), 1, accuracy: tolerance)
    }

    func test_meterValue_atFloor_isZero() {
        // floorDB is -60 dBFS → rms = 10^(-60/20) = 0.001. At the floor, value = 0.
        let floorRMS = pow(Float(10), AudioLevel.floorDB / 20)
        XCTAssertEqual(AudioLevel.meterValue(fromRMS: floorRMS), 0, accuracy: 0.001)
    }

    func test_meterValue_belowFloor_clampsToZero() {
        // Quieter than the floor must not go negative.
        XCTAssertEqual(AudioLevel.meterValue(fromRMS: 0.00001), 0, accuracy: tolerance)
    }

    func test_meterValue_isMonotonic_louderGivesHigher() {
        let quiet = AudioLevel.meterValue(fromRMS: 0.01)
        let mid   = AudioLevel.meterValue(fromRMS: 0.1)
        let loud  = AudioLevel.meterValue(fromRMS: 0.4)
        XCTAssertLessThan(quiet, mid)
        XCTAssertLessThan(mid, loud)
    }

    func test_meterValue_isAlwaysWithinUnitRange() {
        // Property-style sweep: no input should ever escape 0...1.
        for rms in stride(from: Float(0), through: 2, by: 0.05) {
            let v = AudioLevel.meterValue(fromRMS: rms)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    // MARK: - smooth (EMA)

    func test_smooth_movesPartwayTowardTarget() {
        // From 0 toward 1 with factor 0.5 lands exactly halfway.
        XCTAssertEqual(AudioLevel.smooth(previous: 0, target: 1, factor: 0.5),
                       0.5, accuracy: tolerance)
    }

    func test_smooth_factorZero_keepsPreviousValue() {
        XCTAssertEqual(AudioLevel.smooth(previous: 0.3, target: 1, factor: 0),
                       0.3, accuracy: tolerance)
    }

    func test_smooth_factorOne_snapsToTarget() {
        XCTAssertEqual(AudioLevel.smooth(previous: 0.3, target: 0.9, factor: 1),
                       0.9, accuracy: tolerance)
    }

    func test_smooth_convergesTowardTargetOverIterations() {
        // Repeatedly smoothing toward a steady target should approach it.
        var value: Float = 0
        for _ in 0..<50 {
            value = AudioLevel.smooth(previous: value, target: 1, factor: 0.2)
        }
        XCTAssertEqual(value, 1, accuracy: 0.01)
    }

    func test_smooth_clampsOutOfRangeFactor() {
        // A factor above 1 must not overshoot past the target.
        let result = AudioLevel.smooth(previous: 0, target: 1, factor: 5)
        XCTAssertEqual(result, 1, accuracy: tolerance)
    }
}
