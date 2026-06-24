//
//  SubdivisionTests.swift
//  GuitarKitTests
//
//  Tests for the pure subdivision enum. The behavior that matters: each case
//  reports the correct number of ticks per beat (1/2/3/4), since that's the
//  number the sequencer divides the beat spacing by — and `CaseIterable` lists
//  every option for the picker.
//

import XCTest
@testable import GuitarKit

final class SubdivisionTests: XCTestCase {

    func test_ticksPerBeat_matchMusicalMeaning() {
        XCTAssertEqual(Subdivision.quarter.ticksPerBeat, 1)
        XCTAssertEqual(Subdivision.eighth.ticksPerBeat, 2)
        XCTAssertEqual(Subdivision.triplet.ticksPerBeat, 3)
        XCTAssertEqual(Subdivision.sixteenth.ticksPerBeat, 4)
    }

    func test_allCases_coversFourSubdivisions() {
        XCTAssertEqual(Subdivision.allCases,
                       [.quarter, .eighth, .triplet, .sixteenth])
    }

    func test_ticksPerBeat_isAlwaysAtLeastOne() {
        // Important for the sequencer: it divides by this, so it must never be 0.
        for sub in Subdivision.allCases {
            XCTAssertGreaterThanOrEqual(sub.ticksPerBeat, 1)
        }
    }

    func test_labels_areDistinct() {
        let labels = Subdivision.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count)
    }
}
