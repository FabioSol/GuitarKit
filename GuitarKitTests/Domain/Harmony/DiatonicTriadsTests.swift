//
//  DiatonicTriadsTests.swift
//  GuitarKitTests — Harmony domain
//
//  Acceptance criterion: "Each key resolves to ... the seven diatonic triads."
//  We assert both the *qualities* (the I-ii-iii-IV-V-vi-vii° pattern) and the
//  actual chord *roots*, for a major key and a minor key.
//

import XCTest
@testable import GuitarKit

final class DiatonicTriadsTests: XCTestCase {

    func testCMajorHasSevenTriads() {
        let triads = DiatonicTriads.triads(in: Key.major(circlePosition: 0))
        XCTAssertEqual(triads.count, 7)
    }

    func testCMajorTriadQualitiesFollowStandardPattern() {
        let qualities = DiatonicTriads.triads(in: Key.major(circlePosition: 0))
            .map(\.chord.quality)
        XCTAssertEqual(qualities,
                       [.major, .minor, .minor, .major, .major, .minor, .diminished])
    }

    func testCMajorTriadRoots() {
        let roots = DiatonicTriads.triads(in: Key.major(circlePosition: 0))
            .map(\.chord.root)
        XCTAssertEqual(roots, [.c, .d, .e, .f, .g, .a, .b])
    }

    func testCMajorRomanNumerals() {
        let numerals = DiatonicTriads.triads(in: Key.major(circlePosition: 0))
            .map(\.romanNumeral)
        XCTAssertEqual(numerals, ["I", "ii", "iii", "IV", "V", "vi", "vii°"])
    }

    func testCMajorTonicTriadIsCEG() {
        let one = DiatonicTriads.triads(in: Key.major(circlePosition: 0))[0]
        XCTAssertEqual(one.chord.pitchClassSet, [.c, .e, .g])
        XCTAssertEqual(one.degree, 1)
    }

    func testCMajorFiveChordIsGMajor() {
        let five = DiatonicTriads.triads(in: Key.major(circlePosition: 0))[4]
        XCTAssertEqual(five.chord.root, .g)
        XCTAssertEqual(five.chord.quality, .major)
        XCTAssertEqual(five.chord.pitchClassSet, [.g, .b, .d])
    }

    func testCMajorSevenChordIsBDiminished() {
        let seven = DiatonicTriads.triads(in: Key.major(circlePosition: 0))[6]
        XCTAssertEqual(seven.chord.root, .b)
        XCTAssertEqual(seven.chord.quality, .diminished)
        XCTAssertEqual(seven.romanNumeral, "vii°")
    }

    // MARK: - Minor key (natural minor diatonic set)

    func testAMinorTriadQualities() {
        // i ii° III iv v VI VII for natural minor.
        let qualities = DiatonicTriads.triads(in: Key.minor(circlePosition: 0))
            .map(\.chord.quality)
        XCTAssertEqual(qualities,
                       [.minor, .diminished, .major, .minor, .minor, .major, .major])
    }

    func testAMinorTriadRoots() {
        let roots = DiatonicTriads.triads(in: Key.minor(circlePosition: 0))
            .map(\.chord.root)
        XCTAssertEqual(roots, [.a, .b, .c, .d, .e, .f, .g])
    }

    func testAMinorRomanNumerals() {
        let numerals = DiatonicTriads.triads(in: Key.minor(circlePosition: 0))
            .map(\.romanNumeral)
        XCTAssertEqual(numerals, ["i", "ii°", "III", "iv", "v", "VI", "VII"])
    }

    // MARK: - A different major key, to prove it isn't C-specific

    func testGMajorTriadRoots() {
        // G major scale: G A B C D E F♯ → triads rooted on each.
        let roots = DiatonicTriads.triads(in: Key.major(circlePosition: 1))
            .map(\.chord.root)
        XCTAssertEqual(roots, [.g, .a, .b, .c, .d, .e, .fSharp])
    }
}
