//
//  ChromaticZoneTests.swift
//  GuitarKitTests
//
//  Unit tests for the pure chromatic deviation classifier. Because
//  `ChromaticZone.classify` is a plain function (cents in → zone out, no state,
//  no clock, no UI), it's the cheapest, most reliable thing to test — we can pin
//  down every boundary and sign exactly. We deliberately probe the EDGES (the
//  exact ±1 and ±3 cent boundaries) because off-by-a-hair boundary bugs are the
//  classic mistake in threshold code.
//

import XCTest
@testable import GuitarKit

final class ChromaticZoneTests: XCTestCase {

    // MARK: - Perfect window (≤ ±1¢)

    func test_zeroCents_isPerfect() {
        // Dead-on the note is the happiest case.
        XCTAssertEqual(ChromaticZone.classify(cents: 0), .perfect)
    }

    func test_withinOneCent_eitherSign_isPerfect() {
        XCTAssertEqual(ChromaticZone.classify(cents: 0.5), .perfect)
        XCTAssertEqual(ChromaticZone.classify(cents: -0.5), .perfect)
    }

    func test_exactlyOneCent_eitherSign_isPerfect() {
        // The boundary is inclusive (≤±1), so exactly 1¢ is still perfect.
        XCTAssertEqual(ChromaticZone.classify(cents: 1), .perfect)
        XCTAssertEqual(ChromaticZone.classify(cents: -1), .perfect)
    }

    // MARK: - In-tune window (just past perfect, ≤ ±3¢)

    func test_justPastOneCent_isInTune() {
        // Past the perfect window but inside the in-tune window.
        XCTAssertEqual(ChromaticZone.classify(cents: 1.01), .inTune)
        XCTAssertEqual(ChromaticZone.classify(cents: -1.01), .inTune)
    }

    func test_exactlyThreeCents_eitherSign_isInTune() {
        // The in-tune boundary is inclusive (≤±3), so exactly 3¢ is in tune,
        // NOT flat/sharp.
        XCTAssertEqual(ChromaticZone.classify(cents: 3), .inTune)
        XCTAssertEqual(ChromaticZone.classify(cents: -3), .inTune)
    }

    // MARK: - Out of tune → direction (flat / sharp)

    func test_justPastThreeCents_positive_isSharp() {
        // The first value that escapes the in-tune window, on the sharp side.
        XCTAssertEqual(ChromaticZone.classify(cents: 3.01), .sharp)
    }

    func test_justPastThreeCents_negative_isFlat() {
        // ...and on the flat side.
        XCTAssertEqual(ChromaticZone.classify(cents: -3.01), .flat)
    }

    func test_largePositiveCents_isSharp() {
        XCTAssertEqual(ChromaticZone.classify(cents: 40), .sharp)
    }

    func test_largeNegativeCents_isFlat() {
        XCTAssertEqual(ChromaticZone.classify(cents: -40), .flat)
    }

    // MARK: - No reading

    func test_nilCents_isNilZone() {
        // No live pitch → no zone, so callers can show an idle state.
        XCTAssertNil(ChromaticZone.classify(cents: nil))
    }

    // MARK: - Agreement with the named thresholds
    //
    // A guard against the constants and the comparisons drifting apart: classify
    // exactly at each published threshold and assert the documented result.

    func test_thresholdsMatchPublishedConstants() {
        XCTAssertEqual(ChromaticZone.perfectCents, 1)
        XCTAssertEqual(ChromaticZone.inTuneCents, 3)
        XCTAssertEqual(ChromaticZone.classify(cents: ChromaticZone.perfectCents), .perfect)
        XCTAssertEqual(ChromaticZone.classify(cents: ChromaticZone.inTuneCents), .inTune)
    }
}
