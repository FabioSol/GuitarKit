//
//  CapoLabelTests.swift
//  GuitarKitTests
//
//  Behavioural tests for the capo's pure pieces:
//    1. `CapoLabel` — the display/accessibility string helpers.
//    2. `Capo` itself — re-confirming the clamp and the note transposition that
//       the headstock relies on (a capo at fret 2 turns the open low E into F#).
//
//  Everything here is pure value logic, so there's no UI, no main actor, and no
//  async — just plain `XCTAssert`s. These are the tests that "pin" the capo's
//  visible behaviour so a future refactor can't silently change what the chip
//  shows or what notes the pegs name.
//

import XCTest
@testable import GuitarKit

final class CapoLabelTests: XCTestCase {

    // MARK: - badge(for:)

    /// At fret 0 (no capo) there is no counter to show, so the badge is nil.
    /// This is what lets the chip fall back to its quiet "Capo" resting label.
    func test_badge_isNil_atFretZero() {
        XCTAssertNil(CapoLabel.badge(for: .none))
        XCTAssertNil(CapoLabel.badge(for: Capo(fret: 0)))
    }

    /// For every engaged fret 1...12 the badge is "+N". We loop so the test
    /// documents the whole range, including the ceiling (+12).
    func test_badge_isPlusN_forEachEngagedFret() {
        for fret in 1...12 {
            let capo = Capo(fret: fret)
            XCTAssertEqual(CapoLabel.badge(for: capo), "+\(fret)",
                           "Expected badge +\(fret) for a capo on fret \(fret)")
        }
    }

    // MARK: - accessibility(for:)

    /// With no capo, VoiceOver should hear "No capo" — never nil/empty, so the
    /// resting state is still spoken.
    func test_accessibility_noCapo_atFretZero() {
        XCTAssertEqual(CapoLabel.accessibility(for: .none), "No capo")
    }

    /// Engaged frets read as "Capo on fret N".
    func test_accessibility_namesTheFret_whenEngaged() {
        XCTAssertEqual(CapoLabel.accessibility(for: Capo(fret: 1)), "Capo on fret 1")
        XCTAssertEqual(CapoLabel.accessibility(for: Capo(fret: 2)), "Capo on fret 2")
        XCTAssertEqual(CapoLabel.accessibility(for: Capo(fret: 12)), "Capo on fret 12")
    }

    // MARK: - Capo clamp (re-pinned here because the chip depends on it)

    /// A negative requested fret clamps up to 0 (the "no capo" floor).
    func test_capo_clampsBelowZero_toZero() {
        XCTAssertEqual(Capo(fret: -3).fret, 0)
    }

    /// Anything above 12 clamps down to 12 — this is the "stop at the ceiling"
    /// rule the chip's increment relies on (a tap at fret 12 stays at 12).
    func test_capo_clampsAboveTwelve_toTwelve() {
        XCTAssertEqual(Capo(fret: 20).fret, 12)
        XCTAssertEqual(Capo(fret: 13).fret, 12)
    }

    // MARK: - Capo transposition (what the headstock note names depend on)

    /// THE LOAD-BEARING ASSERTION for the headstock: a capo at fret 2 raises the
    /// open low E (E2) by two semitones to F#2. If this ever breaks, the pegs
    /// would name the wrong notes when a capo is on.
    func test_capo_transposesNoteUpByFretCount() {
        let lowE = Note(pitchClass: .e, octave: 2)        // open 6th string
        let shifted = Capo(fret: 2).transpose(lowE)
        XCTAssertEqual(shifted, Note(pitchClass: .fSharp, octave: 2))   // E2 + 2 = F#2
    }

    /// No capo (fret 0) leaves the note exactly where it was — the identity case
    /// that proves the resting chip doesn't accidentally shift anything.
    func test_capo_zeroFret_leavesNoteUnchanged() {
        let a = Note(pitchClass: .a, octave: 4)
        XCTAssertEqual(Capo.none.transpose(a), a)
    }

    /// A shift that crosses an octave boundary still lands correctly: A4 + 3
    /// semitones = C5 (A → A# → B → C, rolling into the next octave).
    func test_capo_transposeCrossesOctaveBoundary() {
        let a4 = Note(pitchClass: .a, octave: 4)
        let shifted = Capo(fret: 3).transpose(a4)
        XCTAssertEqual(shifted, Note(pitchClass: .c, octave: 5))
    }
}
