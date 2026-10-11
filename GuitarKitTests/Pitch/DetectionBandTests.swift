//
//  DetectionBandTests.swift
//  GuitarKitTests
//
//  The tuning-derived detection band, pinned by pure math. The band is the
//  "prior" the selected tuning hands the pitch detector: asymmetric semitone
//  margins around the outermost targets (wide flat side, narrow sharp side),
//  a high-pass corner that follows the low edge, and a low-pass corner that
//  keeps harmonic headroom above the highest string.
//

import XCTest
@testable import GuitarKit

@MainActor
final class DetectionBandTests: XCTestCase {

    /// Build a minimal target — only `frequencyHz` matters to the band.
    private func target(_ hz: Double, index: Int = 0) -> PitchTarget {
        PitchTarget(note: Note(pitchClass: .a, octave: 4), frequencyHz: hz, stringIndex: index)
    }

    // MARK: - Standard guitar (E2 82.407 … E4 329.628)

    func test_standardGuitar_edges() throws {
        let targets = [82.407, 110.0, 146.832, 195.998, 246.942, 329.628]
            .enumerated().map { target($1, index: $0) }
        let band = try XCTUnwrap(DetectionBand.around(targets: targets))

        // Low edge: 5 semitones below low E → 82.407 × 2^(−5/12) ≈ 61.74 Hz.
        XCTAssertEqual(band.minFrequencyHz, 82.407 * pow(2, -5.0 / 12), accuracy: 0.001)
        // High edge: 3 semitones above high E → 329.628 × 2^(3/12) ≈ 392.0 Hz (G4).
        XCTAssertEqual(band.maxFrequencyHz, 329.628 * pow(2, 3.0 / 12), accuracy: 0.001)
        // The high-pass follows the low edge exactly.
        XCTAssertEqual(band.highPassHz, band.minFrequencyHz)
        // The low-pass keeps ~3 harmonics of the top string, NOT the sharp margin.
        XCTAssertEqual(band.lowPassHz, 329.628 * 3, accuracy: 0.001)
        XCTAssertGreaterThan(band.lowPassHz, band.maxFrequencyHz,
                             "harmonic headroom must extend well past the search ceiling")
    }

    // MARK: - 5-string bass (the fixed-corner regression)

    func test_fiveStringBass_lowB_fundamentalPassesTheHighPass() throws {
        // Low B0 is 30.868 Hz. The old fixed 65 Hz high-pass attenuated it by
        // ~12 dB; the derived corner must sit BELOW the fundamental.
        let targets = [30.868, 41.203, 55.0, 73.416, 97.999]
            .enumerated().map { target($1, index: $0) }
        let band = try XCTUnwrap(DetectionBand.around(targets: targets))

        XCTAssertLessThan(band.highPassHz, 30.868,
                          "the low B fundamental must pass the high-pass")
        XCTAssertEqual(band.minFrequencyHz, 30.868 * pow(2, -5.0 / 12), accuracy: 0.001)
        // Still above the absolute floor that keeps search lags inside the buffer.
        XCTAssertGreaterThanOrEqual(band.minFrequencyHz, 20)
    }

    // MARK: - Edges and clamps

    func test_absoluteFloor_clampsVeryLowTargets() throws {
        // A (hypothetical) 22 Hz target: −5 semitones would be ~16.5 Hz, below
        // the 20 Hz floor that keeps the longest search lag inside the buffer.
        let band = try XCTUnwrap(DetectionBand.around(targets: [target(22)]))
        XCTAssertEqual(band.minFrequencyHz, 20)
        XCTAssertEqual(band.highPassHz, 20)
    }

    func test_emptyTargets_returnsNil() {
        XCTAssertNil(DetectionBand.around(targets: []),
                     "no targets → no prior; callers fall back to .full")
    }

    func test_nonPositiveFrequency_returnsNil() {
        XCTAssertNil(DetectionBand.around(targets: [target(0)]))
    }

    func test_fullBand_cornersFollowTheSameDerivationRules() {
        // No fixed corners anywhere: .full's corners obey the same rules as a
        // tuning-derived band — high-pass at the low edge, low-pass with
        // harmonic headroom over the ceiling.
        XCTAssertEqual(DetectionBand.full.minFrequencyHz, 30)
        XCTAssertEqual(DetectionBand.full.maxFrequencyHz, 1500)
        XCTAssertEqual(DetectionBand.full.highPassHz, DetectionBand.full.minFrequencyHz)
        XCTAssertEqual(DetectionBand.full.lowPassHz,
                       DetectionBand.full.maxFrequencyHz * 3, accuracy: 0.001)
    }

    func test_singleTarget_producesValidBand() throws {
        // One string (e.g. mid-edit): band still well-formed around it.
        let band = try XCTUnwrap(DetectionBand.around(targets: [target(440)]))
        XCTAssertLessThan(band.minFrequencyHz, 440)
        XCTAssertGreaterThan(band.maxFrequencyHz, 440)
        XCTAssertLessThan(band.maxFrequencyHz, band.lowPassHz)
    }
}
