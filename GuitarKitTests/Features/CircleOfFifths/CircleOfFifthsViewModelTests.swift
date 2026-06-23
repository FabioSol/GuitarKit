//
//  CircleOfFifthsViewModelTests.swift
//  GuitarKitTests — Circle of Fifths feature
//
//  Unit tests for the *view-model logic only* — the small amount of behaviour
//  slice #18 adds on top of the (already-tested) harmony domain: selection,
//  the rotation-to-home maths, seat indexing, the scale chosen per key, and the
//  no-op playback hooks. We deliberately do NOT re-test music theory here (key
//  signatures, diatonic chords, etc.) — that's covered by the Harmony tests.
//
//  We use XCTest to match the rest of the suite.
//

import XCTest
@testable import GuitarKit

final class CircleOfFifthsViewModelTests: XCTestCase {

    // MARK: - Initial state

    func testStartsOnCMajorWithNoRotation() {
        let vm = CircleOfFifthsViewModel()
        XCTAssertEqual(vm.selectedKey, CircleOfFifths.majorKeys[0]) // C major
        XCTAssertEqual(vm.rotationDegrees, 0, accuracy: 0.0001)
    }

    // MARK: - Selection updates the selected key

    func testSelectingAKeyUpdatesSelection() {
        let vm = CircleOfFifthsViewModel()
        let g = CircleOfFifths.majorKeys[1] // G major, seat 1
        vm.select(g)
        XCTAssertEqual(vm.selectedKey, g)
    }

    // MARK: - Seat indexing (shared seats across both rings)

    func testSeatIndexMatchesRingPosition() {
        let vm = CircleOfFifthsViewModel()
        // Major seats are 0..<12 in clockwise order.
        XCTAssertEqual(vm.seatIndex(of: CircleOfFifths.majorKeys[0]), 0) // C
        XCTAssertEqual(vm.seatIndex(of: CircleOfFifths.majorKeys[1]), 1) // G
        XCTAssertEqual(vm.seatIndex(of: CircleOfFifths.majorKeys[6]), 6) // F♯
        // A minor and C major share seat 0 (relative keys on the same spoke).
        XCTAssertEqual(vm.seatIndex(of: CircleOfFifths.minorKeys[0]), 0) // A minor
        XCTAssertEqual(vm.seatIndex(of: CircleOfFifths.minorKeys[1]), 1) // E minor
    }

    // MARK: - Rotation-to-home maths

    func testRotationBringsSelectedSeatToTop() {
        let vm = CircleOfFifthsViewModel()
        // Seat 0 needs no rotation.
        XCTAssertEqual(vm.rotationToHome(for: CircleOfFifths.majorKeys[0]), 0, accuracy: 0.0001)
        // Seat 1 (G) sits 30° clockwise, so the wheel rotates -30° to bring it up.
        XCTAssertEqual(vm.rotationToHome(for: CircleOfFifths.majorKeys[1]), -30, accuracy: 0.0001)
        // Seat 3 (A) → -90°.
        XCTAssertEqual(vm.rotationToHome(for: CircleOfFifths.majorKeys[3]), -90, accuracy: 0.0001)
        // Seat 6 (F♯, the bottom) → -180°.
        XCTAssertEqual(vm.rotationToHome(for: CircleOfFifths.majorKeys[6]), -180, accuracy: 0.0001)
    }

    func testSelectingAlsoUpdatesRotation() {
        let vm = CircleOfFifthsViewModel()
        vm.select(CircleOfFifths.majorKeys[3]) // A major, seat 3
        XCTAssertEqual(vm.rotationDegrees, -90, accuracy: 0.0001)
    }

    func testSelectingAMinorUsesSameSeatRotation() {
        let vm = CircleOfFifthsViewModel()
        // E minor shares seat 1 with G major, so it rotates to -30° too.
        vm.select(CircleOfFifths.minorKeys[1])
        XCTAssertEqual(vm.rotationDegrees, -30, accuracy: 0.0001)
    }

    // MARK: - Scale chosen per key

    func testScaleForMajorKeyIsMajorScale() {
        let vm = CircleOfFifthsViewModel()
        let scale = vm.scale(for: CircleOfFifths.majorKeys[1]) // G major
        XCTAssertEqual(scale.type, .major)
        XCTAssertEqual(scale.root, .g)
    }

    func testScaleForMinorKeyIsNaturalMinorScale() {
        let vm = CircleOfFifthsViewModel()
        let aMinor = CircleOfFifths.minorKeys[0]
        let scale = vm.scale(for: aMinor)
        XCTAssertEqual(scale.type, .naturalMinor)
        XCTAssertEqual(scale.root, aMinor.tonic.pitchClass) // A
    }

    // MARK: - Derived details delegate to the harmony domain

    func testRelativeKeyOfCMajorIsAMinor() {
        let vm = CircleOfFifthsViewModel()
        vm.select(CircleOfFifths.majorKeys[0]) // C major
        XCTAssertEqual(vm.relativeKey, CircleOfFifths.minorKeys[0]) // A minor
        XCTAssertEqual(vm.relativeKey.mode, .minor)
    }

    func testDiatonicChordsHasSevenDegrees() {
        let vm = CircleOfFifthsViewModel()
        vm.select(CircleOfFifths.majorKeys[0]) // C major
        let chords = vm.diatonicChords
        XCTAssertEqual(chords.count, 7)
        // Degree 1 is the tonic (C major's I), degree 7 the leading-tone triad.
        XCTAssertEqual(chords.first?.degree, 1)
        XCTAssertEqual(chords.first?.romanNumeral, "I")
    }

    // MARK: - No-op playback hooks (reserved for slice #13)

    func testPlayScaleHookFiresWithSelectedKeysScale() {
        let vm = CircleOfFifthsViewModel()

        // Capture what the hook was handed. `var` captured by the closure lets us
        // record the argument for assertion after `select(_:)` runs.
        var played: Scale?
        vm.onPlayScale = { played = $0 }

        vm.select(CircleOfFifths.majorKeys[1]) // G major

        XCTAssertEqual(played?.type, .major)
        XCTAssertEqual(played?.root, .g)
    }

    func testNoCrashWhenPlaybackHooksAreNil() {
        // With both hooks left nil (the default for this slice), selecting must
        // still work and simply make no sound. This guards the "audio is out of
        // scope" contract.
        let vm = CircleOfFifthsViewModel()
        XCTAssertNil(vm.onPlayScale)
        XCTAssertNil(vm.onPlayChord)
        vm.select(CircleOfFifths.majorKeys[2]) // D major — should not crash
        XCTAssertEqual(vm.selectedKey, CircleOfFifths.majorKeys[2])
    }
}
