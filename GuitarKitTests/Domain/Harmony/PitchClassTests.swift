//
//  PitchClassTests.swift
//  GuitarKitTests — Harmony domain
//
//  These tests pin down the *foundation* the rest of the harmony layer stands
//  on: 12-tone wrap-around transposition and semitone distances. Everything
//  else (chords, scales, keys) is built from `transposed(by:)`, so if this is
//  right the higher-level note sets have a solid base.
//

import XCTest
@testable import GuitarKit

final class PitchClassTests: XCTestCase {

    func testTransposeWithinOctave() {
        // C up a major third (4 semitones) is E.
        XCTAssertEqual(PitchClass.c.transposed(by: 4), .e)
    }

    func testTransposeWrapsAroundTop() {
        // B up one semitone wraps back to C.
        XCTAssertEqual(PitchClass.b.transposed(by: 1), .c)
    }

    func testTransposeByNegativeWrapsAroundBottom() {
        // C down one semitone wraps to B.
        XCTAssertEqual(PitchClass.c.transposed(by: -1), .b)
    }

    func testTransposeByOctaveIsIdentity() {
        // Up 12 semitones lands on the same pitch class.
        for pc in PitchClass.allCases {
            XCTAssertEqual(pc.transposed(by: 12), pc)
        }
    }

    func testTransposeByLargeOffsetWraps() {
        // Offsets well beyond an octave (used by 13th chords) still reduce
        // correctly: C + 14 (a ninth) == D, the same PC as C + 2.
        XCTAssertEqual(PitchClass.c.transposed(by: 14), .d)
    }

    func testSemitoneDistance() {
        // C up to E is 4; E up to C wraps to 8.
        XCTAssertEqual(PitchClass.e.semitoneDistance(from: .c), 4)
        XCTAssertEqual(PitchClass.c.semitoneDistance(from: .e), 8)
        XCTAssertEqual(PitchClass.c.semitoneDistance(from: .c), 0)
    }
}
