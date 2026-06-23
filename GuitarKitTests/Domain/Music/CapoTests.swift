//
//  CapoTests.swift
//  GuitarKitTests
//
//  Behavioral tests for capo transposition: shifts all targets by N semitones
//  and clamps the fret to 0...12.
//

import XCTest
@testable import GuitarKit

final class CapoTests: XCTestCase {

    private let tolerance = 0.01

    private let standardGuitar: [Note] = [
        Note(pitchClass: .e, octave: 2),
        Note(pitchClass: .a, octave: 2),
        Note(pitchClass: .d, octave: 3),
        Note(pitchClass: .g, octave: 3),
        Note(pitchClass: .b, octave: 3),
        Note(pitchClass: .e, octave: 4),
    ]

    // MARK: Clamping

    func test_capo_clampsNegativeToZero() {
        XCTAssertEqual(Capo(fret: -5).fret, 0)
    }

    func test_capo_clampsAboveTwelveToTwelve() {
        XCTAssertEqual(Capo(fret: 20).fret, 12)
    }

    func test_capo_acceptsInRangeValues() {
        XCTAssertEqual(Capo(fret: 0).fret, 0)
        XCTAssertEqual(Capo(fret: 7).fret, 7)
        XCTAssertEqual(Capo(fret: 12).fret, 12)
    }

    func test_capo_isEngagedOnlyWhenAboveZero() {
        XCTAssertFalse(Capo(fret: 0).isEngaged)
        XCTAssertTrue(Capo(fret: 1).isEngaged)
    }

    // MARK: Single-note transposition

    func test_capo_shiftsNoteUpBySemitones() {
        // Low E (E2) with capo at fret 2 sounds F#2.
        let e2 = Note(pitchClass: .e, octave: 2)
        XCTAssertEqual(Capo(fret: 2).transpose(e2),
                       Note(pitchClass: .fSharp, octave: 2))
    }

    func test_capo_fret0_isIdentity() {
        let g3 = Note(pitchClass: .g, octave: 3)
        XCTAssertEqual(Capo(fret: 0).transpose(g3), g3)
    }

    // MARK: Whole-tuning transposition through the calculator

    func test_capo_shiftsAllTargetsUp() {
        let calc = PitchCalculator()
        let open = calc.targets(for: standardGuitar)
        let capoed = calc.targets(for: standardGuitar, capo: Capo(fret: 2))

        // Every string's sounding note rises by 2 semitones...
        for i in 0..<6 {
            XCTAssertEqual(capoed[i].note.midiNumber,
                           open[i].note.midiNumber + 2)
        }
        // ...and the capo'd low E sounds at F#2's frequency.
        let fSharp2 = Note(pitchClass: .fSharp, octave: 2)
        XCTAssertEqual(capoed[0].frequencyHz, calc.frequency(of: fSharp2), accuracy: tolerance)
    }

    func test_capo_at12_raisesByOctave_doublesFrequency() {
        let calc = PitchCalculator()
        let open = calc.targets(for: standardGuitar)
        let capoed = calc.targets(for: standardGuitar, capo: Capo(fret: 12))
        for i in 0..<6 {
            // An octave up is exactly double the frequency.
            XCTAssertEqual(capoed[i].frequencyHz, open[i].frequencyHz * 2, accuracy: tolerance)
        }
    }

    func test_capo_clampPreventsBeyondOctaveShift() {
        // Requesting fret 15 clamps to 12, so the shift is exactly one octave.
        let calc = PitchCalculator()
        let open = calc.targets(for: standardGuitar)
        let capoed = calc.targets(for: standardGuitar, capo: Capo(fret: 15))
        XCTAssertEqual(capoed[0].frequencyHz, open[0].frequencyHz * 2, accuracy: tolerance)
    }
}
