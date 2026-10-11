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
    //
    // We use HARMONIC-RICH tones (a fundamental plus overtones), not pure sines,
    // because that's what a real instrument produces — and because HPS, by design,
    // needs a harmonic series to work (a lone sine has nothing to multiply). Pure
    // sines stay covered for MPM/YIN in their own test files.

    func test_everyAlgorithm_detectsConcertA() {
        let s = Signal.harmonicTone(fundamental: 440, harmonicAmplitudes: [1.0, 0.5, 0.3, 0.2],
                                    sampleRate: sampleRate)
        for algorithm in PitchAlgorithm.allCases {
            let estimate = algorithm.detect(samples: s, sampleRate: sampleRate)
            XCTAssertLessThanOrEqual(cents(estimate, from: 440), 8,
                                     "\(algorithm.label) missed concert A")
        }
    }

    func test_everyAlgorithm_detectsGuitarLowE() {
        // A realistic low E whose fundamental is weaker than its 2nd harmonic.
        let s = Signal.harmonicTone(fundamental: 82.41, harmonicAmplitudes: [0.5, 1.0, 0.7, 0.4],
                                    sampleRate: sampleRate)
        for algorithm in PitchAlgorithm.allCases {
            let estimate = algorithm.detect(samples: s, sampleRate: sampleRate)
            XCTAssertLessThanOrEqual(cents(estimate, from: 82.41), 8,
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

    // MARK: - Ensemble fusion rule (pure, exhaustive)
    //
    // Forcing MPM and YIN to genuinely DISAGREE from real audio is impractical —
    // they're both autocorrelation-family and tend to agree (even agreeing on the
    // same octave error). So we test the fusion RULE directly via the pure
    // `combine`, feeding synthetic estimates to hit every branch deterministically.

    func test_combine_agreement_blendsAndBoostsClarity() {
        // Two estimates ~15¢ apart (inside the 40¢ window) → blended toward the
        // more-confident one, with clarity nudged above the better single detector.
        let mpm = PitchEstimate(frequency: 220.0, clarity: 0.7)
        let yin = PitchEstimate(frequency: 222.0, clarity: 0.9)   // ~15.6¢ above
        let fused = PitchAlgorithm.combine(mpm: mpm, yin: yin)
        XCTAssertNotNil(fused)
        // Clarity-weighted blend sits between the two, nearer YIN (higher clarity).
        XCTAssertGreaterThan(fused!.frequency, 220.0)
        XCTAssertLessThan(fused!.frequency, 222.0)
        XCTAssertGreaterThan(fused!.frequency, 221.0)
        // Corroboration boosts confidence above either input (capped at 1).
        XCTAssertGreaterThan(fused!.clarity, 0.9)
        XCTAssertLessThanOrEqual(fused!.clarity, 1.0)
    }

    func test_combine_disagreement_trustsMoreConfident() {
        // An octave apart (1200¢, well past the 40¢ window) → no blend; pick the
        // detector with the higher clarity verbatim.
        let mpm = PitchEstimate(frequency: 110.0, clarity: 0.55)   // fundamental
        let yin = PitchEstimate(frequency: 220.0, clarity: 0.92)   // octave error, but surer
        let fused = PitchAlgorithm.combine(mpm: mpm, yin: yin)
        XCTAssertEqual(fused, yin, "the more confident estimate should win outright")
    }

    func test_combine_disagreement_picksMpmWhenItIsSurer() {
        let mpm = PitchEstimate(frequency: 82.0, clarity: 0.9)
        let yin = PitchEstimate(frequency: 164.0, clarity: 0.6)
        XCTAssertEqual(PitchAlgorithm.combine(mpm: mpm, yin: yin), mpm)
    }

    func test_combine_singleDetector_passesThrough() {
        let only = PitchEstimate(frequency: 196.0, clarity: 0.8)
        XCTAssertEqual(PitchAlgorithm.combine(mpm: only, yin: nil), only)
        XCTAssertEqual(PitchAlgorithm.combine(mpm: nil, yin: only), only)
    }

    func test_combine_neitherDetector_isNil() {
        XCTAssertNil(PitchAlgorithm.combine(mpm: nil, yin: nil))
    }

    // MARK: - HPS as the disagreement tie-breaker

    func test_combine_disagreement_hpsBreaksTieTowardItsCorroboration() {
        // YIN is more confident but octave-wrong (220); MPM has the true f0 (110).
        // Without HPS the more-confident YIN would win — but HPS corroborates MPM,
        // so MPM should win.
        let mpm = PitchEstimate(frequency: 110, clarity: 0.80)
        let yin = PitchEstimate(frequency: 220, clarity: 0.95)
        let hps = PitchEstimate(frequency: 109, clarity: 0.90)
        XCTAssertEqual(PitchAlgorithm.combine(mpm: mpm, yin: yin, hps: hps), mpm)
        // Sanity: without HPS the confident (wrong) YIN wins.
        XCTAssertEqual(PitchAlgorithm.combine(mpm: mpm, yin: yin), yin)
    }

    func test_combine_disagreement_hpsCorroboratesYin() {
        let mpm = PitchEstimate(frequency: 82, clarity: 0.90)
        let yin = PitchEstimate(frequency: 164, clarity: 0.60)
        let hps = PitchEstimate(frequency: 165, clarity: 0.85)
        XCTAssertEqual(PitchAlgorithm.combine(mpm: mpm, yin: yin, hps: hps), yin)
    }

    func test_combine_disagreement_hpsCorroboratesNeither_fallsBackToConfident() {
        // HPS lands on a third value far from both → it can't break the tie, so the
        // more-confident detector wins.
        let mpm = PitchEstimate(frequency: 110, clarity: 0.60)
        let yin = PitchEstimate(frequency: 220, clarity: 0.90)
        let hps = PitchEstimate(frequency: 330, clarity: 0.80)
        XCTAssertEqual(PitchAlgorithm.combine(mpm: mpm, yin: yin, hps: hps), yin)
    }

    func test_combine_agreement_ignoresHps() {
        // When MPM and YIN agree, HPS is irrelevant even if it's wildly off.
        let mpm = PitchEstimate(frequency: 220, clarity: 0.80)
        let yin = PitchEstimate(frequency: 221, clarity: 0.80)
        let hps = PitchEstimate(frequency: 440, clarity: 0.99)
        let fused = PitchAlgorithm.combine(mpm: mpm, yin: yin, hps: hps)
        XCTAssertNotNil(fused)
        XCTAssertEqual(Double(fused!.frequency), 220.5, accuracy: 1.0,
                       "agreement should blend MPM+YIN and ignore HPS")
    }

    // MARK: - HPS laziness (the FFT must only run when the tie-breaker is consulted)

    /// A side-effecting HPS provider, so tests can observe WHETHER the
    /// `@autoclosure` was evaluated — the stand-in for "did the big FFT run".
    private func trackedHPS(_ estimate: PitchEstimate?, _ evaluated: inout Bool) -> PitchEstimate? {
        evaluated = true
        return estimate
    }

    func test_combine_agreement_neverEvaluatesHps() {
        var hpsRan = false
        let mpm = PitchEstimate(frequency: 220, clarity: 0.80)
        let yin = PitchEstimate(frequency: 221, clarity: 0.80)
        _ = PitchAlgorithm.combine(mpm: mpm, yin: yin,
                                   hps: trackedHPS(PitchEstimate(frequency: 220, clarity: 0.9), &hpsRan))
        XCTAssertFalse(hpsRan, "agreement must not pay for the HPS FFT")
    }

    func test_combine_singleDetector_neverEvaluatesHps() {
        var hpsRan = false
        let only = PitchEstimate(frequency: 220, clarity: 0.80)
        _ = PitchAlgorithm.combine(mpm: only, yin: nil,
                                   hps: trackedHPS(nil, &hpsRan))
        XCTAssertFalse(hpsRan, "a single-detector frame has no tie to break")
    }

    func test_combine_disagreement_evaluatesHpsExactlyThen() {
        var hpsRan = false
        let mpm = PitchEstimate(frequency: 110, clarity: 0.80)
        let yin = PitchEstimate(frequency: 220, clarity: 0.95)
        _ = PitchAlgorithm.combine(mpm: mpm, yin: yin,
                                   hps: trackedHPS(PitchEstimate(frequency: 109, clarity: 0.9), &hpsRan))
        XCTAssertTrue(hpsRan, "disagreement is the one branch that consults HPS")
    }
}
