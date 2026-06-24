//
//  PitchAlgorithmTests.swift
//  GuitarKitTests
//
//  Tests for the swappable/ensemble layer: every algorithm recovers a known
//  pitch, and the ensemble corroborates agreeing detectors (boosting clarity)
//  while still returning something sensible on noise-free tones.
//

import XCTest
@testable import GuitarKit

final class PitchAlgorithmTests: XCTestCase {

    private let sampleRate = 44_100.0

    private func cents(_ estimate: PitchEstimate?, from expected: Double) -> Double {
        guard let estimate else { return .infinity }
        return abs(PitchCalculator.cents(from: Double(estimate.frequency), to: expected))
    }

    // MARK: - Each algorithm recovers a known pitch

    func test_everyAlgorithm_detectsConcertA() {
        let s = Signal.sine(frequency: 440, sampleRate: sampleRate)
        for algorithm in PitchAlgorithm.allCases {
            let estimate = algorithm.detect(samples: s, sampleRate: sampleRate)
            XCTAssertLessThanOrEqual(cents(estimate, from: 440), 5,
                                     "\(algorithm.label) missed concert A")
        }
    }

    func test_everyAlgorithm_detectsGuitarLowE() {
        let s = Signal.sine(frequency: 82.41, sampleRate: sampleRate)
        for algorithm in PitchAlgorithm.allCases {
            let estimate = algorithm.detect(samples: s, sampleRate: sampleRate)
            XCTAssertLessThanOrEqual(cents(estimate, from: 82.41), 6,
                                     "\(algorithm.label) missed low E")
        }
    }

    // MARK: - Ensemble behavior

    func test_ensemble_corroboration_boostsClarityOverEither() {
        // On a clean tone MPM and YIN agree, so the ensemble should be at least as
        // confident as the better single detector.
        let s = Signal.sine(frequency: 196, sampleRate: sampleRate)   // G3
        let mpm = PitchAlgorithm.mpm.detect(samples: s, sampleRate: sampleRate)
        let yin = PitchAlgorithm.yin.detect(samples: s, sampleRate: sampleRate)
        let ensemble = PitchAlgorithm.ensemble.detect(samples: s, sampleRate: sampleRate)

        let best = max(mpm?.clarity ?? 0, yin?.clarity ?? 0)
        XCTAssertNotNil(ensemble)
        XCTAssertGreaterThanOrEqual(ensemble?.clarity ?? 0, best)
        XCTAssertLessThanOrEqual(cents(ensemble, from: 196), 5)
    }

    func test_ensemble_returnsNil_onSilence() {
        let silence = [Float](repeating: 0, count: 4_096)
        XCTAssertNil(PitchAlgorithm.ensemble.detect(samples: silence, sampleRate: sampleRate))
    }
}
