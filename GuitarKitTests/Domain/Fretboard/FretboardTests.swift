//
//  FretboardTests.swift
//  GuitarKitTests
//
//  Tests for the tuning-aware fretboard mapping + scale projection: notes at
//  positions, capo shift, scale membership / root / degree, and the
//  Current ⇄ Standard override changing the mapping.
//

import XCTest
@testable import GuitarKit

final class FretboardTests: XCTestCase {

    private func n(_ pc: PitchClass, _ oct: Int) -> Note { Note(pitchClass: pc, octave: oct) }

    private var standardGuitar: Fretboard {
        Fretboard(tuning: InstrumentLibrary.guitar6.tunings[0])  // EADGBE
    }

    // MARK: - Note mapping

    func test_openLowE_isE2() {
        XCTAssertEqual(standardGuitar.note(string: 0, fret: 0), n(.e, 2))
    }

    func test_lowEString_fret5_isA2() {
        // 5 semitones above E2 = A2 (the classic "tune the 5th fret" reference).
        XCTAssertEqual(standardGuitar.note(string: 0, fret: 5), n(.a, 2))
    }

    func test_highEString_open_isE4() {
        XCTAssertEqual(standardGuitar.note(string: 5, fret: 0), n(.e, 4))
    }

    func test_outOfRange_returnsNil() {
        XCTAssertNil(standardGuitar.note(string: 99, fret: 0))
        XCTAssertNil(standardGuitar.note(string: 0, fret: -1))
    }

    // MARK: - Capo

    func test_capo2_raisesEveryOpenString() {
        let capoed = Fretboard(tuning: InstrumentLibrary.guitar6.tunings[0], capo: Capo(fret: 2))
        // Low E open, capo 2 → F#2.
        XCTAssertEqual(capoed.note(string: 0, fret: 0), n(.fSharp, 2))
        // And fret 3 on top of the capo → A2.
        XCTAssertEqual(capoed.note(string: 0, fret: 3), n(.a, 2))
    }

    func test_capo_shortensReachableNeck() {
        // A capo at fret 2 on a 12-fret board leaves only 10 frets above it; asking
        // past that must return nil (no phantom notes above the real neck).
        let capoed = Fretboard(tuning: InstrumentLibrary.guitar6.tunings[0],
                               capo: Capo(fret: 2), fretCount: 12)
        XCTAssertNotNil(capoed.note(string: 0, fret: 10))
        XCTAssertNil(capoed.note(string: 0, fret: 11))
    }

    // MARK: - Scale membership / root / degree

    func test_cMajor_membership_onLowEString() {
        let fs = FretboardScale(fretboard: standardGuitar, scale: Scale(root: .c, type: .major))
        // E (open, fret 0) is in C major (C D E F G A B).
        XCTAssertTrue(fs.isInScale(string: 0, fret: 0))
        // F (fret 1) is in C major.
        XCTAssertTrue(fs.isInScale(string: 0, fret: 1))
        // F# (fret 2) is NOT in C major.
        XCTAssertFalse(fs.isInScale(string: 0, fret: 2))
    }

    func test_cMajor_root_onAString() {
        let fs = FretboardScale(fretboard: standardGuitar, scale: Scale(root: .c, type: .major))
        // A string (string 1 = A2) fret 3 = C3 → a root.
        XCTAssertTrue(fs.isRoot(string: 1, fret: 3))
        XCTAssertEqual(fs.degree(string: 1, fret: 3), 1)        // root = degree 1
        // E on the low E string is the 3rd degree of C major.
        XCTAssertEqual(fs.degree(string: 0, fret: 0), 3)
        // F# isn't in the scale → no degree.
        XCTAssertNil(fs.degree(string: 0, fret: 2))
    }

    // MARK: - Current ⇄ Standard override

    func test_dropD_vs_standard_differ_onSixthString() {
        let standard = Fretboard(tuning: InstrumentLibrary.guitar6.tunings[0])      // …low E
        let dropD = Fretboard(tuning: InstrumentLibrary.guitar6.tunings[1])         // Drop D → low D
        XCTAssertEqual(standard.note(string: 0, fret: 0), n(.e, 2))
        XCTAssertEqual(dropD.note(string: 0, fret: 0), n(.d, 2))
    }

    // MARK: - Ascending notes

    func test_ascendingNotes_areSortedAndInScale() {
        let fs = FretboardScale(
            fretboard: Fretboard(tuning: InstrumentLibrary.guitar6.tunings[0], fretCount: 12),
            scale: Scale(root: .c, type: .major)
        )
        let notes = fs.ascendingNotes()
        XCTAssertFalse(notes.isEmpty)
        // Sorted ascending by pitch.
        XCTAssertEqual(notes.map(\.midiNumber), notes.map(\.midiNumber).sorted())
        // Every note is a C-major pitch class (no accidentals).
        let cMajor = Scale(root: .c, type: .major).pitchClassSet
        XCTAssertTrue(notes.allSatisfy { cMajor.contains($0.pitchClass) })
    }
}
