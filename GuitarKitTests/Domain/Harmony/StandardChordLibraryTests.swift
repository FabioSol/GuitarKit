//
//  StandardChordLibraryTests.swift
//  GuitarKitTests
//
//  The curated open-chord catalogue is HAND-AUTHORED `[Int?]` fret data, so a typo
//  could silently ship a wrong chord (an E♭ where an E should be, a major where a
//  minor was meant). These tests pin every shape by playing it on a standard-guitar
//  fretboard and checking the notes it sounds actually spell the named chord.
//
//  THE MUSICAL CONTRACT we assert for each shape:
//    1. NO WRONG NOTES — every sounded pitch class is a tone of the chord.
//    2. The ROOT is present.
//    3. The quality-defining tones are present: the THIRD (which separates major
//       from minor) and, for seventh chords, the SEVENTH.
//  The PERFECT FIFTH is the one tone allowed to be missing — guitarists routinely
//  omit it (e.g. the open C7, x32310, has no G), so requiring it would be wrong.
//

import XCTest
@testable import GuitarKit

final class StandardChordLibraryTests: XCTestCase {

    /// A standard-guitar board (EADGBE) — the only tuning the curated shapes claim
    /// to be correct for.
    private let board = Fretboard(openStrings: StandardChordLibrary.standardGuitarOpenStrings)

    /// The pitch classes a `[Int?]` shape actually sounds on the board.
    private func soundedPitchClasses(_ frets: [Int?]) -> Set<PitchClass> {
        var result: Set<PitchClass> = []
        for (string, fret) in frets.enumerated() {
            guard let fret, let note = board.note(string: string, fret: fret) else { continue }
            result.insert(note.pitchClass)
        }
        return result
    }

    // MARK: - Every curated shape spells its chord

    func test_everyCuratedShape_spellsItsChord() {
        for (key, voicing) in StandardChordLibrary.shapes {
            let chord = Chord(root: key.root, quality: key.quality)
            let tones = chord.pitchClassSet
            let sounded = soundedPitchClasses(voicing.frets)
            let name = "\(key.root.name)\(key.quality)"

            // 1) No wrong notes.
            XCTAssertTrue(sounded.isSubset(of: tones),
                "\(name): sounds \(sounded.sorted { $0.rawValue < $1.rawValue }) — not all chord tones \(tones.sorted { $0.rawValue < $1.rawValue })")

            // 2) Root present.
            XCTAssertTrue(sounded.contains(key.root), "\(name): missing its root")

            // 3) Third present (the major/minor discriminator).
            let thirdInterval = key.quality.semitoneOffsets.first { $0 == 3 || $0 == 4 }
            if let thirdInterval {
                XCTAssertTrue(sounded.contains(key.root.transposed(by: thirdInterval)),
                    "\(name): missing its third")
            }

            // 4) Seventh present for seventh qualities (the only missing tone we
            //    permit is the perfect fifth).
            let missing = tones.subtracting(sounded)
            let perfectFifth = key.root.transposed(by: 7)
            XCTAssertTrue(missing.isSubset(of: [perfectFifth]),
                "\(name): omits more than the fifth (missing \(missing.sorted { $0.rawValue < $1.rawValue }))")
        }
    }

    // MARK: - A few famous shapes pinned exactly (a typo-canary on the data itself)

    func test_famousShapes_areExactlyTheKnownFrets() {
        XCTAssertEqual(StandardChordLibrary.voicing(root: .c, quality: .major)?.frets,
                       [nil, 3, 2, 0, 1, 0], "C major must be x32010")
        XCTAssertEqual(StandardChordLibrary.voicing(root: .g, quality: .major)?.frets,
                       [3, 2, 0, 0, 0, 3], "G major must be 320003")
        XCTAssertEqual(StandardChordLibrary.voicing(root: .e, quality: .minor)?.frets,
                       [0, 2, 2, 0, 0, 0], "E minor must be 022000")
        XCTAssertEqual(StandardChordLibrary.voicing(root: .d, quality: .dominantSeventh)?.frets,
                       [nil, nil, 0, 2, 1, 2], "D7 must be xx0212")
    }

    // MARK: - Lookup contract

    func test_unauthoredChord_returnsNil() {
        // There is no standard OPEN C-minor shape, so the library must return nil
        // (the caller then falls back to the generator).
        XCTAssertNil(StandardChordLibrary.voicing(root: .c, quality: .minor))
    }

    func test_isStandardGuitar_onlyForExactEADGBE() {
        XCTAssertTrue(StandardChordLibrary.isStandardGuitar(
            openStrings: StandardChordLibrary.standardGuitarOpenStrings))
        // Drop D (low string D2 instead of E2) is NOT standard.
        var dropD = StandardChordLibrary.standardGuitarOpenStrings
        dropD[0] = Note(pitchClass: .d, octave: 2)
        XCTAssertFalse(StandardChordLibrary.isStandardGuitar(openStrings: dropD))
    }
}
