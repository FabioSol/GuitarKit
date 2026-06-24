//
//  BeatAccentTests.swift
//  GuitarKitTests
//
//  Tests for the pure beat-accent enum. The behavior that matters: tapping a
//  dot cycles accent → normal → muted → accent, so `next` must follow that exact
//  order (the tap-a-dot gesture relies on it).
//

import XCTest
@testable import GuitarKit

final class BeatAccentTests: XCTestCase {

    func test_next_cyclesAccentNormalMuted() {
        XCTAssertEqual(BeatAccent.accent.next, .normal)
        XCTAssertEqual(BeatAccent.normal.next, .muted)
        XCTAssertEqual(BeatAccent.muted.next,  .accent)
    }

    func test_next_returnsToStartAfterThreeTaps() {
        // Three cycles bring us back to where we began — a full loop.
        XCTAssertEqual(BeatAccent.accent.next.next.next, .accent)
    }

    func test_allCases_coversThreeStates() {
        XCTAssertEqual(BeatAccent.allCases, [.accent, .normal, .muted])
    }

    func test_displayHints_areDistinct() {
        let hints = BeatAccent.allCases.map(\.displayHint)
        XCTAssertEqual(Set(hints).count, hints.count)
    }
}
