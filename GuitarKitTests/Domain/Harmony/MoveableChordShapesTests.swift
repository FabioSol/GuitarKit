//
//  MoveableChordShapesTests.swift
//  GuitarKitTests — Harmony domain
//
//  Pins the moveable (barre) shape bank and the generator's playability filter:
//    1. Placement is correct — the classic forms land on the expected frets.
//    2. Every placed shape sounds ONLY chord tones (no wrong notes baked in).
//    3. Every placed shape is physically playable.
//    4. The playability filter accepts real barre chords and rejects five-finger
//       scatter shapes.
//    5. End to end, the Chords view model only surfaces playable shapes.
//

import XCTest
@testable import GuitarKit

final class MoveableChordShapesTests: XCTestCase {

    /// Standard guitar EADGBE, generous neck so barres up high have room.
    private func standardBoard(fretCount: Int = 15) -> Fretboard {
        Fretboard(tuning: InstrumentLibrary.guitar6.tunings[0], fretCount: fretCount)
    }

    // MARK: - 1. Placement

    func test_eShapeMajor_atRootE_isOpenEChord() {
        // The E-shape at index fret 0 is just the open E major chord (022100).
        let voicings = MoveableChordLibrary.voicings(root: .e, quality: .major, on: standardBoard())
        XCTAssertTrue(voicings.contains(ChordVoicing(frets: [0, 2, 2, 1, 0, 0])),
            "E-shape major rooted on E should be the open E chord")
    }

    func test_cMajor_producesKnownBarreShapes() {
        let voicings = MoveableChordLibrary.voicings(root: .c, quality: .major, on: standardBoard())
        // A-shape C barre at fret 3 (x35553) and E-shape C barre at fret 8.
        XCTAssertTrue(voicings.contains(ChordVoicing(frets: [nil, 3, 5, 5, 5, 3])),
            "Expected the A-shape C barre at fret 3")
        XCTAssertTrue(voicings.contains(ChordVoicing(frets: [8, 10, 10, 9, 8, 8])),
            "Expected the E-shape C barre at fret 8")
    }

    func test_voicings_areOrderedUpTheNeck() {
        let voicings = MoveableChordLibrary.voicings(root: .g, quality: .major, on: standardBoard())
        let heights = voicings.map { $0.lowestFrettedFret ?? 0 }
        XCTAssertEqual(heights, heights.sorted(), "Voicings should climb the neck low → high")
    }

    // MARK: - 2 & 3. Every placed shape is in-chord AND playable

    func test_everyMoveableShape_isInChordAndPlayable() {
        let board = standardBoard()
        let roots: [PitchClass] = [.c, .cSharp, .d, .e, .f, .fSharp, .g, .a, .b]
        let qualities: [ChordQuality] = [
            .major, .minor, .dominantSeventh, .majorSeventh, .minorSeventh,
            .sus2, .sus4, .sixth, .minorSixth
        ]
        for root in roots {
            for quality in qualities {
                let chord = Chord(root: root, quality: quality)
                let voicings = MoveableChordLibrary.voicings(root: root, quality: quality, on: board)
                XCTAssertFalse(voicings.isEmpty,
                    "\(root.name)\(quality.symbol) should yield at least one moveable shape")
                for voicing in voicings {
                    let sounded = voicing.playedPitchClasses(on: board)
                    XCTAssertTrue(sounded.isSubset(of: chord.pitchClassSet),
                        "\(root.name)\(quality.symbol) \(voicing.frets) sounded \(sounded), not all chord tones")
                    XCTAssertTrue(ChordVoicingGenerator.isPlayable(voicing, on: board),
                        "\(root.name)\(quality.symbol) \(voicing.frets) should be playable")
                    // The root must be present (it's a real voicing of the chord).
                    XCTAssertTrue(sounded.contains(root),
                        "\(root.name)\(quality.symbol) \(voicing.frets) is missing its root")
                }
            }
        }
    }

    // MARK: - 4. The playability filter

    func test_isPlayable_acceptsBarreChord() {
        let board = standardBoard()
        // F major barre: six notes, three on the first fret (one barre finger).
        XCTAssertTrue(ChordVoicingGenerator.isPlayable(ChordVoicing(frets: [1, 3, 3, 2, 1, 1]), on: board))
    }

    func test_isPlayable_acceptsOpenChord() {
        let board = standardBoard()
        XCTAssertTrue(ChordVoicingGenerator.isPlayable(ChordVoicing(frets: [nil, 3, 2, 0, 1, 0]), on: board))
    }

    func test_isPlayable_rejectsFiveFingerScatter() {
        let board = standardBoard()
        // Five distinct fretted notes, none shareable by a barre → not fingerable.
        XCTAssertFalse(ChordVoicingGenerator.isPlayable(ChordVoicing(frets: [2, 3, 4, 5, 6, nil]), on: board))
    }

    func test_isPlayable_rejectsTooWideSpan() {
        let board = standardBoard()
        XCTAssertFalse(ChordVoicingGenerator.isPlayable(ChordVoicing(frets: [2, nil, nil, nil, nil, 9]), on: board))
    }

    // MARK: - 5. End-to-end via the view model

    @MainActor
    func test_viewModel_cMajor_onlySurfacesPlayableShapes() {
        let model = ChordsViewModel()        // no store → standard guitar
        model.root = .c
        model.quality = .major
        let voicings = model.alternateVoicings
        let board = model.fretboard

        XCTAssertGreaterThanOrEqual(voicings.count, 2, "Expected an open shape plus barres to cycle")
        for voicing in voicings {
            XCTAssertTrue(ChordVoicingGenerator.isPlayable(voicing, on: board),
                "Surfaced \(voicing.frets) is not playable")
        }
        // At least one shape sits up the neck (a barre), proving cycling climbs.
        XCTAssertTrue(voicings.contains { ($0.lowestFrettedFret ?? 0) > 1 },
            "Expected at least one up-the-neck barre voicing")
    }

    @MainActor
    func test_viewModel_uncuratedQuality_stillPlayable() {
        // F# major has no curated OPEN shape, but the moveable bank still covers it.
        let model = ChordsViewModel()
        model.root = .fSharp
        model.quality = .major
        let board = model.fretboard
        XCTAssertFalse(model.alternateVoicings.isEmpty)
        for voicing in model.alternateVoicings {
            XCTAssertTrue(ChordVoicingGenerator.isPlayable(voicing, on: board))
        }
    }
}
