//
//  PitchResolutionTests.swift
//  GuitarKitTests
//
//  Tests for `PitchCalculator.nearestNote(toFrequency:)` — the inverse of the
//  tuning formula that turns a measured frequency into "which note, how off?".
//

import XCTest
@testable import GuitarKit

final class PitchResolutionTests: XCTestCase {

    // Default calculator: A = 440 Hz, equal temperament.
    private let calc = PitchCalculator()

    func test_concertA_resolvesToA4_zeroCents() {
        let result = calc.nearestNote(toFrequency: 440)
        XCTAssertEqual(result?.note, Note(pitchClass: .a, octave: 4))
        XCTAssertEqual(result?.centOffset ?? .nan, 0, accuracy: 0.01)
    }

    func test_aSharp4_resolvesCorrectly() {
        // A#4 is one equal-tempered semitone above A4: 440 · 2^(1/12) ≈ 466.16.
        let result = calc.nearestNote(toFrequency: 440 * pow(2.0, 1.0 / 12.0))
        XCTAssertEqual(result?.note, Note(pitchClass: .aSharp, octave: 4))
        XCTAssertEqual(result?.centOffset ?? .nan, 0, accuracy: 0.01)
    }

    func test_octaveBelow_resolvesToA3() {
        let result = calc.nearestNote(toFrequency: 220)
        XCTAssertEqual(result?.note, Note(pitchClass: .a, octave: 3))
        XCTAssertEqual(result?.centOffset ?? .nan, 0, accuracy: 0.01)
    }

    func test_sharpOfA4_reportsPositiveCents() {
        // 10 cents sharp of A4: 440 · 2^(10/1200).
        let hz = 440 * pow(2.0, 10.0 / 1200.0)
        let result = calc.nearestNote(toFrequency: hz)
        XCTAssertEqual(result?.note, Note(pitchClass: .a, octave: 4))
        XCTAssertEqual(result?.centOffset ?? .nan, 10, accuracy: 0.01)
    }

    func test_flatOfA4_reportsNegativeCents() {
        // 15 cents flat of A4.
        let hz = 440 * pow(2.0, -15.0 / 1200.0)
        let result = calc.nearestNote(toFrequency: hz)
        XCTAssertEqual(result?.note, Note(pitchClass: .a, octave: 4))
        XCTAssertEqual(result?.centOffset ?? .nan, -15, accuracy: 0.01)
    }

    func test_guitarLowE_resolvesToE2() {
        let result = calc.nearestNote(toFrequency: 82.41)
        XCTAssertEqual(result?.note, Note(pitchClass: .e, octave: 2))
        // 82.41 is the rounded standard value, within a cent of exact E2.
        XCTAssertEqual(result?.centOffset ?? .nan, 0, accuracy: 1.0)
    }

    func test_nonPositiveFrequency_returnsNil() {
        XCTAssertNil(calc.nearestNote(toFrequency: 0))
        XCTAssertNil(calc.nearestNote(toFrequency: -100))
    }

    func test_respectsReferencePitch() {
        // With A = 442, a 442 Hz tone should read as a dead-on A4.
        let calc442 = PitchCalculator(referenceA: ReferencePitch(hertz: 442))
        let result = calc442.nearestNote(toFrequency: 442)
        XCTAssertEqual(result?.note, Note(pitchClass: .a, octave: 4))
        XCTAssertEqual(result?.centOffset ?? .nan, 0, accuracy: 0.01)
    }
}
