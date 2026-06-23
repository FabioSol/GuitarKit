//
//  ScaleTests.swift
//  GuitarKitTests — Harmony domain
//
//  Acceptance criterion: "Scales/modes ... resolve to the correct note sets."
//  We assert the exact pitch classes each scale produces from a given root,
//  through the public `Scale` API.
//

import XCTest
@testable import GuitarKit

final class ScaleTests: XCTestCase {

    // MARK: - Major & minor

    func testCMajorScale() {
        let scale = Scale(root: .c, type: .major)
        XCTAssertEqual(scale.notes, [.c, .d, .e, .f, .g, .a, .b])
    }

    func testANaturalMinorScale() {
        // The relative minor of C major: the white keys starting on A.
        let scale = Scale(root: .a, type: .naturalMinor)
        XCTAssertEqual(scale.notes, [.a, .b, .c, .d, .e, .f, .g])
    }

    func testAHarmonicMinorRaisesSeventh() {
        // Natural minor A B C D E F G with G raised to G♯.
        let scale = Scale(root: .a, type: .harmonicMinor)
        XCTAssertEqual(scale.notes, [.a, .b, .c, .d, .e, .f, .gSharp])
    }

    func testAMelodicMinorRaisesSixthAndSeventh() {
        // A B C D E F♯ G♯ (ascending form).
        let scale = Scale(root: .a, type: .melodicMinor)
        XCTAssertEqual(scale.notes, [.a, .b, .c, .d, .e, .fSharp, .gSharp])
    }

    // MARK: - Pentatonics & blues

    func testCMajorPentatonic() {
        let scale = Scale(root: .c, type: .majorPentatonic)
        XCTAssertEqual(scale.notes, [.c, .d, .e, .g, .a])
        XCTAssertEqual(scale.noteCount, 5)
    }

    func testAMinorPentatonic() {
        let scale = Scale(root: .a, type: .minorPentatonic)
        XCTAssertEqual(scale.notes, [.a, .c, .d, .e, .g])
    }

    func testCBluesScale() {
        // Minor pentatonic on C plus the ♭5 (G♭).
        let scale = Scale(root: .c, type: .blues)
        XCTAssertEqual(scale.notes, [.c, .dSharp, .f, .fSharp, .g, .aSharp])
        XCTAssertEqual(scale.noteCount, 6)
    }

    // MARK: - The seven modes (all rooted on C so the contrast is clear)

    func testIonianEqualsMajor() {
        XCTAssertEqual(Scale(root: .c, type: .ionian).pitchClassSet,
                       Scale(root: .c, type: .major).pitchClassSet)
    }

    func testAeolianEqualsNaturalMinor() {
        XCTAssertEqual(Scale(root: .c, type: .aeolian).pitchClassSet,
                       Scale(root: .c, type: .naturalMinor).pitchClassSet)
    }

    func testCDorian() {
        // C D E♭ F G A B♭ — minor with a natural 6th (A).
        XCTAssertEqual(Scale(root: .c, type: .dorian).notes,
                       [.c, .d, .dSharp, .f, .g, .a, .aSharp])
    }

    func testCPhrygian() {
        // C D♭ E♭ F G A♭ B♭ — minor with a ♭2.
        XCTAssertEqual(Scale(root: .c, type: .phrygian).notes,
                       [.c, .cSharp, .dSharp, .f, .g, .gSharp, .aSharp])
    }

    func testCLydian() {
        // C D E F♯ G A B — major with a ♯4.
        XCTAssertEqual(Scale(root: .c, type: .lydian).notes,
                       [.c, .d, .e, .fSharp, .g, .a, .b])
    }

    func testCMixolydian() {
        // C D E F G A B♭ — major with a ♭7.
        XCTAssertEqual(Scale(root: .c, type: .mixolydian).notes,
                       [.c, .d, .e, .f, .g, .a, .aSharp])
    }

    func testCLocrian() {
        // C D♭ E♭ F G♭ A♭ B♭ — ♭2 and ♭5; its tonic triad is diminished.
        XCTAssertEqual(Scale(root: .c, type: .locrian).notes,
                       [.c, .cSharp, .dSharp, .f, .fSharp, .gSharp, .aSharp])
    }

    // MARK: - Modes are rotations of one parent scale

    func testDDorianUsesSameNotesAsCMajor() {
        // D Dorian is the C-major collection started on D — a great sanity check
        // that the mode recipes line up with the major scale.
        XCTAssertEqual(Scale(root: .d, type: .dorian).pitchClassSet,
                       Scale(root: .c, type: .major).pitchClassSet)
    }
}
