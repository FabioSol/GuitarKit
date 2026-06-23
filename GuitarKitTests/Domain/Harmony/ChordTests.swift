//
//  ChordTests.swift
//  GuitarKitTests — Harmony domain
//
//  Acceptance criterion: "chord qualities resolve to the correct note sets
//  (including extended/altered qualities)." We root nearly everything on C so
//  the expected notes are easy to read and verify by hand, and we compare as
//  *sets* (order- and duplicate-independent) since pitch-class membership is
//  what the fretboard layer consumes.
//

import XCTest
@testable import GuitarKit

final class ChordTests: XCTestCase {

    /// Tiny helper: build a C-rooted chord and return its pitch-class set.
    private func cChord(_ quality: ChordQuality) -> Set<PitchClass> {
        Chord(root: .c, quality: quality).pitchClassSet
    }

    // MARK: - Triads

    func testMajorTriad()      { XCTAssertEqual(cChord(.major), [.c, .e, .g]) }
    func testMinorTriad()      { XCTAssertEqual(cChord(.minor), [.c, .dSharp, .g]) }
    func testDiminishedTriad() { XCTAssertEqual(cChord(.diminished), [.c, .dSharp, .fSharp]) }
    func testAugmentedTriad()  { XCTAssertEqual(cChord(.augmented), [.c, .e, .gSharp]) }
    func testSus2()            { XCTAssertEqual(cChord(.sus2), [.c, .d, .g]) }
    func testSus4()            { XCTAssertEqual(cChord(.sus4), [.c, .f, .g]) }

    // MARK: - Added-note & sixth chords

    func testAdd9() { XCTAssertEqual(cChord(.add9), [.c, .e, .g, .d]) }
    func testSixth() { XCTAssertEqual(cChord(.sixth), [.c, .e, .g, .a]) }
    func testMinorSixth() { XCTAssertEqual(cChord(.minorSixth), [.c, .dSharp, .g, .a]) }
    func testSixNine() { XCTAssertEqual(cChord(.sixNine), [.c, .e, .g, .a, .d]) }

    // MARK: - Sevenths

    func testDominantSeventh()   { XCTAssertEqual(cChord(.dominantSeventh), [.c, .e, .g, .aSharp]) }
    func testMajorSeventh()      { XCTAssertEqual(cChord(.majorSeventh), [.c, .e, .g, .b]) }
    func testMinorSeventh()      { XCTAssertEqual(cChord(.minorSeventh), [.c, .dSharp, .g, .aSharp]) }
    func testMinorMajorSeventh() { XCTAssertEqual(cChord(.minorMajorSeventh), [.c, .dSharp, .g, .b]) }
    func testHalfDiminished()    { XCTAssertEqual(cChord(.halfDiminished), [.c, .dSharp, .fSharp, .aSharp]) }
    func testDiminishedSeventh() { XCTAssertEqual(cChord(.diminishedSeventh), [.c, .dSharp, .fSharp, .a]) }
    func testAugmentedSeventh()  { XCTAssertEqual(cChord(.augmentedSeventh), [.c, .e, .gSharp, .aSharp]) }

    // MARK: - Extended chords

    func testDominantNinth() {
        XCTAssertEqual(cChord(.dominantNinth), [.c, .e, .g, .aSharp, .d])
    }

    func testDominantEleventh() {
        // 3rd omitted by convention: root, 5, ♭7, 9, 11.
        XCTAssertEqual(cChord(.dominantEleventh), [.c, .g, .aSharp, .d, .f])
        // Specifically assert the major 3rd (E) is NOT present.
        XCTAssertFalse(cChord(.dominantEleventh).contains(.e))
    }

    func testDominantThirteenth() {
        // 11th omitted by convention; 13th (A) present.
        XCTAssertEqual(cChord(.dominantThirteenth), [.c, .e, .g, .aSharp, .d, .a])
        XCTAssertFalse(cChord(.dominantThirteenth).contains(.f)) // no 11th
    }

    func testMajorNinth() {
        XCTAssertEqual(cChord(.majorNinth), [.c, .e, .g, .b, .d])
    }

    func testMinorNinth() {
        XCTAssertEqual(cChord(.minorNinth), [.c, .dSharp, .g, .aSharp, .d])
    }

    // MARK: - Altered dominants

    func testDominantSeventhFlatNine() {
        // ♭9 of C is D♭ (== C♯ pitch class).
        XCTAssertEqual(cChord(.dominantSeventhFlatNine), [.c, .e, .g, .aSharp, .cSharp])
    }

    func testDominantSeventhSharpNine() {
        // ♯9 of C is D♯ — the "Hendrix chord" colour.
        XCTAssertEqual(cChord(.dominantSeventhSharpNine), [.c, .e, .g, .aSharp, .dSharp])
    }

    // MARK: - Root independence & membership

    func testQualityIsRootIndependent() {
        // A major chord is the same shape from any root: G major = G B D.
        XCTAssertEqual(Chord(root: .g, quality: .major).pitchClassSet, [.g, .b, .d])
    }

    func testContains() {
        let cMajor = Chord(root: .c, quality: .major)
        XCTAssertTrue(cMajor.contains(.e))
        XCTAssertFalse(cMajor.contains(.f))
    }

    func testEveryQualityProducesNotes() {
        // Smoke test across the whole catalogue: every quality yields a
        // non-empty set that includes the root.
        for quality in ChordQuality.allCases {
            let chord = Chord(root: .c, quality: quality)
            XCTAssertFalse(chord.pitchClassSet.isEmpty, "\(quality) produced no notes")
            XCTAssertTrue(chord.contains(.c), "\(quality) is missing its root")
        }
    }
}
