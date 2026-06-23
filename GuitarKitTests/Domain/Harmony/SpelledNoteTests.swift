//
//  SpelledNoteTests.swift
//  GuitarKitTests — Harmony domain
//
//  Verifies the spelling layer: a letter + accidental maps to the right sounding
//  pitch class and the right display name, and enharmonic spellings (F♯ vs G♭)
//  share a pitch class while differing in name.
//

import XCTest
@testable import GuitarKit

final class SpelledNoteTests: XCTestCase {

    func testNaturalPitchClasses() {
        XCTAssertEqual(SpelledNote(letter: .c).pitchClass, .c)
        XCTAssertEqual(SpelledNote(letter: .e).pitchClass, .e)
        XCTAssertEqual(SpelledNote(letter: .b).pitchClass, .b)
    }

    func testSharpAndFlatPitchClasses() {
        XCTAssertEqual(SpelledNote(letter: .f, accidental: +1).pitchClass, .fSharp)
        XCTAssertEqual(SpelledNote(letter: .g, accidental: -1).pitchClass, .fSharp)
    }

    func testEnharmonicsShareAPitchClassButNotAName() {
        let fSharp = SpelledNote(letter: .f, accidental: +1)
        let gFlat  = SpelledNote(letter: .g, accidental: -1)
        XCTAssertEqual(fSharp.pitchClass, gFlat.pitchClass) // same sound
        XCTAssertNotEqual(fSharp, gFlat)                    // different spelling
        XCTAssertEqual(fSharp.name, "F♯")
        XCTAssertEqual(gFlat.name, "G♭")
    }

    func testDoubleAccidentalName() {
        XCTAssertEqual(SpelledNote(letter: .f, accidental: +2).name, "F♯♯")
        XCTAssertEqual(SpelledNote(letter: .b, accidental: -2).name, "B♭♭")
    }

    func testLetterAdvanceWraps() {
        XCTAssertEqual(Letter.b.advanced(by: 1), .c)
        XCTAssertEqual(Letter.c.advanced(by: -1), .b)
        XCTAssertEqual(Letter.c.advanced(by: 4), .g)
    }
}
