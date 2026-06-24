//
//  TimeSignatureTests.swift
//  GuitarKitTests
//
//  Tests for the pure time-signature value. The behaviors that matter: the
//  common presets carry the right beat counts and labels, and the custom
//  initializer CLAMPS any out-of-range beat count into the allowed window so no
//  input path can produce a 0- or 99-beat bar.
//

import XCTest
@testable import GuitarKit

final class TimeSignatureTests: XCTestCase {

    // MARK: - Presets

    func test_presets_haveCorrectBeatCounts() {
        XCTAssertEqual(TimeSignature.twoFour.beatsPerBar, 2)
        XCTAssertEqual(TimeSignature.threeFour.beatsPerBar, 3)
        XCTAssertEqual(TimeSignature.fourFour.beatsPerBar, 4)
        XCTAssertEqual(TimeSignature.fiveFour.beatsPerBar, 5)
        XCTAssertEqual(TimeSignature.sixEight.beatsPerBar, 6)
        XCTAssertEqual(TimeSignature.sevenEight.beatsPerBar, 7)
    }

    func test_presets_haveCorrectLabels() {
        XCTAssertEqual(TimeSignature.fourFour.label, "4/4")
        XCTAssertEqual(TimeSignature.sixEight.label, "6/8")
        XCTAssertEqual(TimeSignature.sevenEight.label, "7/8")
    }

    func test_presetsList_isInExpectedOrder() {
        XCTAssertEqual(TimeSignature.presets,
                       [.twoFour, .threeFour, .fourFour, .fiveFour, .sixEight, .sevenEight])
    }

    // MARK: - Custom beat count + clamping

    func test_custom_inRange_isStoredAsIs() {
        XCTAssertEqual(TimeSignature(beatsPerBar: 9).beatsPerBar, 9)
    }

    func test_custom_belowMin_clampsUp() {
        // 0 and negatives clamp to the floor (1).
        XCTAssertEqual(TimeSignature(beatsPerBar: 0).beatsPerBar, TimeSignature.minBeats)
        XCTAssertEqual(TimeSignature(beatsPerBar: -5).beatsPerBar, TimeSignature.minBeats)
    }

    func test_custom_aboveMax_clampsDown() {
        XCTAssertEqual(TimeSignature(beatsPerBar: 99).beatsPerBar, TimeSignature.maxBeats)
    }

    func test_custom_defaultsToQuarterNoteValue() {
        XCTAssertEqual(TimeSignature(beatsPerBar: 5).noteValue, 4)
    }

    // MARK: - Equality

    func test_equality_comparesBeatsAndNoteValue() {
        XCTAssertEqual(TimeSignature(beatsPerBar: 4), TimeSignature.fourFour)
        XCTAssertNotEqual(TimeSignature(beatsPerBar: 6, noteValue: 8),
                          TimeSignature(beatsPerBar: 6, noteValue: 4))
    }
}
