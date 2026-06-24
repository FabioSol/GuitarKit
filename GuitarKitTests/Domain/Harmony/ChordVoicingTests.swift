//
//  ChordVoicingTests.swift
//  GuitarKitTests — Harmony domain
//
//  Acceptance criterion (issue #20): "voicing generation is covered by unit
//  tests." These pin the generator's two core promises and the curated library:
//
//    1. Every note a generated voicing sounds is a chord tone (in-chord shapes).
//    2. A C-major shape in standard tuning actually contains a C (it's that chord).
//    3. Alternate voicings climb the neck (each later one sits no lower than the
//       previous), so "cycle up the neck" really moves up.
//    4. The curated standard-library C-major shape is the known x32010 voicing.
//
//  We build a standard-guitar `Fretboard` to test on, since the curated library
//  and the classic shapes are defined for that tuning.
//

import XCTest
@testable import GuitarKit

final class ChordVoicingTests: XCTestCase {

    /// Standard guitar tuning EADGBE, no capo — the board we voice chords on.
    /// We use a generous fret count so alternates have room to climb the neck.
    private func standardGuitarBoard(fretCount: Int = 15) -> Fretboard {
        Fretboard(tuning: InstrumentLibrary.guitar6.tunings[0], fretCount: fretCount)
    }

    // MARK: - 1. Generated voicings contain ONLY chord tones

    func testGeneratedVoicingContainsOnlyChordTones() {
        let board = standardGuitarBoard()

        // Sweep a representative spread of roots × qualities; for each, every note
        // the generated shape sounds must be a member of the chord's pitch-class
        // set. This is the generator's central invariant.
        let roots: [PitchClass] = [.c, .e, .g, .a, .d, .fSharp]
        let qualities: [ChordQuality] = [.major, .minor, .dominantSeventh, .minorSeventh, .majorSeventh]

        for root in roots {
            for quality in qualities {
                let chord = Chord(root: root, quality: quality)
                let voicing = ChordVoicingGenerator.voicing(for: chord, on: board)
                let sounded = voicing.playedPitchClasses(on: board)

                // Every sounded pitch class must be in the chord. (`isSubset` is the
                // clean way to say "no stray, non-chord notes.")
                XCTAssertTrue(
                    sounded.isSubset(of: chord.pitchClassSet),
                    "\(root.name)\(quality.symbol) voicing sounded \(sounded) — not all chord tones \(chord.pitchClassSet)"
                )
            }
        }
    }

    func testGeneratedVoicingIsNonEmptyForCommonChords() {
        let board = standardGuitarBoard()
        // A sanity floor: the common open chords should produce *some* sounding
        // strings, not an all-muted shape.
        for root in [PitchClass.c, .a, .g, .e, .d] {
            let voicing = ChordVoicingGenerator.voicing(for: Chord(root: root, quality: .major), on: board)
            XCTAssertFalse(
                voicing.soundingStringIndices.isEmpty,
                "\(root.name) major generated an all-muted shape"
            )
        }
    }

    // MARK: - 2. A C-major voicing includes a C

    func testCMajorVoicingIncludesC() {
        let board = standardGuitarBoard()
        let chord = Chord(root: .c, quality: .major)
        let voicing = ChordVoicingGenerator.voicing(for: chord, on: board)

        XCTAssertTrue(
            voicing.playedPitchClasses(on: board).contains(.c),
            "A C-major voicing must actually contain a C"
        )
    }

    func testCMajorGeneratedShapeIsRootPosition() {
        // The root-in-bass preference should make the LOWEST sounding note a C.
        let board = standardGuitarBoard()
        let voicing = ChordVoicingGenerator.voicing(for: Chord(root: .c, quality: .major), on: board)
        let lowestNote = voicing.playedNotes(on: board).first

        XCTAssertEqual(lowestNote?.pitchClass, .c, "C major's bass note should be C (root position)")
    }

    // MARK: - 3. Alternates climb the neck

    func testAlternatesAreOrderedUpTheNeck() {
        let board = standardGuitarBoard()
        let alternates = ChordVoicingGenerator.alternates(for: Chord(root: .c, quality: .major), on: board)

        // There should be more than one shape to cycle through for a major chord.
        XCTAssertGreaterThan(alternates.count, 1, "Expected multiple C-major voicings to cycle through")

        // Each successive shape must sit at the same height or higher than the one
        // before it — never lower. (We treat a pure-open shape's height as 0.)
        let heights = alternates.map { $0.lowestFrettedFret ?? 0 }
        for i in 1..<heights.count {
            XCTAssertGreaterThanOrEqual(
                heights[i], heights[i - 1],
                "Alternate \(i) (fret \(heights[i])) is lower than alternate \(i - 1) (fret \(heights[i - 1]))"
            )
        }

        // And the LAST alternate must be strictly higher up the neck than the FIRST
        // — proving "cycle up the neck" genuinely moves up.
        XCTAssertGreaterThan(
            heights.last ?? 0, heights.first ?? 0,
            "The highest alternate should sit further up the neck than the first"
        )
    }

    func testEveryAlternateStaysWithinTheFretSpan() {
        // Each generated shape must be physically playable: its fingered notes span
        // no more than the heuristic's window (so it fits under one hand).
        let board = standardGuitarBoard()
        let alternates = ChordVoicingGenerator.alternates(for: Chord(root: .g, quality: .major), on: board)

        for voicing in alternates {
            guard let low = voicing.lowestFrettedFret, let high = voicing.highestFret else { continue }
            XCTAssertLessThanOrEqual(
                high - low, ChordVoicingGenerator.windowSpan,
                "Voicing \(voicing.frets) spans more than \(ChordVoicingGenerator.windowSpan) frets"
            )
        }
    }

    // MARK: - 4. The curated library's C-major is x32010

    func testStandardLibraryCMajorIsKnownShape() {
        // The classic open C major: x32010 (low → high: mute, 3, 2, 0, 1, 0).
        let voicing = StandardChordLibrary.voicing(root: .c, quality: .major)
        XCTAssertEqual(voicing?.frets, [nil, 3, 2, 0, 1, 0], "Curated C major should be x32010")
    }

    func testStandardLibraryCMajorSoundsAllChordTones() {
        // Sanity: the hand-authored shape must sound exactly the C-major triad on a
        // standard board (no typo slipped a wrong note in).
        let board = standardGuitarBoard()
        guard let voicing = StandardChordLibrary.voicing(root: .c, quality: .major) else {
            return XCTFail("Expected a curated C major shape")
        }
        XCTAssertEqual(voicing.playedPitchClasses(on: board), [.c, .e, .g])
    }

    func testStandardLibraryOpenEMajorIsKnownShape() {
        // A second pin so the table is genuinely checked: open E major is 022100.
        let voicing = StandardChordLibrary.voicing(root: .e, quality: .major)
        XCTAssertEqual(voicing?.frets, [0, 2, 2, 1, 0, 0], "Curated E major should be 022100")
    }

    func testStandardLibraryReturnsNilForUncuratedChord() {
        // A chord with no hand-authored open shape (e.g. F# minor) returns nil so
        // the caller falls through to the generator.
        XCTAssertNil(StandardChordLibrary.voicing(root: .fSharp, quality: .minor))
    }

    func testIsStandardGuitarRecognizesStandardTuning() {
        XCTAssertTrue(StandardChordLibrary.isStandardGuitar(openStrings: standardGuitarBoard().openStrings))
        // Drop D is NOT standard tuning, so the library shouldn't claim it.
        let dropD = Fretboard(tuning: InstrumentLibrary.guitar6.tunings[1])
        XCTAssertFalse(StandardChordLibrary.isStandardGuitar(openStrings: dropD.openStrings))
    }

    // MARK: - ChordVoicing helpers

    func testVoicingDerivedFacts() {
        // x32010: lowest fingered fret = 1, highest = 3, one muted string.
        let v = ChordVoicing(frets: [nil, 3, 2, 0, 1, 0])
        XCTAssertEqual(v.lowestFrettedFret, 1)
        XCTAssertEqual(v.highestFret, 3)
        XCTAssertEqual(v.mutedStringCount, 1)
        XCTAssertEqual(v.soundingStringIndices, [1, 2, 3, 4, 5]) // string 0 muted
    }
}
