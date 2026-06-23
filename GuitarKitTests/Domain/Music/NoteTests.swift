//
//  NoteTests.swift
//  GuitarKitTests
//
//  Behavioral tests for Note <-> MIDI conversion, asserted through the public
//  interface only (no peeking at internals).
//

import XCTest
@testable import GuitarKit

final class NoteTests: XCTestCase {

    // MARK: Note -> MIDI

    func test_midiNumber_forReferenceA4_is69() {
        let a4 = Note(pitchClass: .a, octave: 4)
        XCTAssertEqual(a4.midiNumber, 69)
    }

    func test_midiNumber_forMiddleC4_is60() {
        let c4 = Note(pitchClass: .c, octave: 4)
        XCTAssertEqual(c4.midiNumber, 60)
    }

    func test_midiNumber_forLowGuitarE2_is40() {
        let e2 = Note(pitchClass: .e, octave: 2)
        XCTAssertEqual(e2.midiNumber, 40)
    }

    func test_midiNumber_forLowBassE1_is28() {
        // Standard 4-string bass low E is E1 = MIDI 28 (full range incl. bass).
        let e1 = Note(pitchClass: .e, octave: 1)
        XCTAssertEqual(e1.midiNumber, 28)
    }

    // MARK: MIDI -> Note

    func test_fromMidi_69_isA4() {
        XCTAssertEqual(Note.from(midiNumber: 69), Note(pitchClass: .a, octave: 4))
    }

    func test_fromMidi_61_isCSharp4() {
        XCTAssertEqual(Note.from(midiNumber: 61), Note(pitchClass: .cSharp, octave: 4))
    }

    // MARK: Round-trip — the strongest correctness property

    func test_midiRoundTrip_isStableAcrossFullRange() {
        // For every MIDI number across (and beyond) the app's instrument range,
        // Note -> MIDI -> Note must return the same note.
        for midi in 0...108 {
            let note = Note.from(midiNumber: midi)
            XCTAssertEqual(note.midiNumber, midi, "round trip failed at MIDI \(midi)")
        }
    }

    // MARK: Display names

    func test_name_usesSharpSpellingWithOctave() {
        XCTAssertEqual(Note(pitchClass: .fSharp, octave: 3).name, "F#3")
        XCTAssertEqual(Note(pitchClass: .a, octave: 4).name, "A4")
    }

    // MARK: PitchClass ordering

    func test_pitchClass_isOrderedChromatically() {
        XCTAssertTrue(PitchClass.c < PitchClass.cSharp)
        XCTAssertTrue(PitchClass.a < PitchClass.b)
        XCTAssertEqual(PitchClass.allCases.count, 12)
    }
}
