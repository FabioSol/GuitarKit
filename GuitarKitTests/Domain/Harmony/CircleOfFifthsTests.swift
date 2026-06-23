//
//  CircleOfFifthsTests.swift
//  GuitarKitTests — Harmony domain
//
//  Tests the circle-of-fifths *adjacency* relationships: who sits next to whom,
//  the ordered rings, and distances. These feed the Circle tool's wheel.
//

import XCTest
@testable import GuitarKit

final class CircleOfFifthsTests: XCTestCase {

    func testTwelveMajorKeysInClockwiseOrder() {
        let names = CircleOfFifths.majorKeys.map(\.tonic.name)
        XCTAssertEqual(names,
                       ["C", "G", "D", "A", "E", "B", "F♯",
                        "D♭", "A♭", "E♭", "B♭", "F"])
    }

    func testInnerRingIsRelativeMinors() {
        // minorKeys[i] must be the relative minor of majorKeys[i].
        XCTAssertEqual(CircleOfFifths.minorKeys.first?.tonic.name, "A")   // inside C
        XCTAssertEqual(CircleOfFifths.minorKeys[1].tonic.name, "E")       // inside G
        for (major, minor) in zip(CircleOfFifths.majorKeys, CircleOfFifths.minorKeys) {
            XCTAssertEqual(major.relative, minor)
            XCTAssertEqual(minor.mode, .minor)
        }
    }

    func testNextGoesUpAFifth() {
        // One step clockwise from C major is G major.
        XCTAssertEqual(CircleOfFifths.next(Key.major(circlePosition: 0)).tonic.name, "G")
    }

    func testPreviousGoesDownAFifth() {
        // One step anticlockwise from C major is F major.
        XCTAssertEqual(CircleOfFifths.previous(Key.major(circlePosition: 0)).tonic.name, "F")
    }

    func testClockwiseWrapsAround() {
        // From F (the last seat), one more clockwise wraps back to C.
        let f = Key.major(circlePosition: -1)
        XCTAssertEqual(CircleOfFifths.next(f).tonic.name, "C")
    }

    func testNeighborsOfCMajor() {
        let (prev, next) = CircleOfFifths.neighbors(of: Key.major(circlePosition: 0))
        XCTAssertEqual(prev.tonic.name, "F")
        XCTAssertEqual(next.tonic.name, "G")
    }

    func testAdjacencyPreservesMinorMode() {
        // Stepping clockwise from A minor lands on E minor (still minor).
        let aMinor = Key.minor(circlePosition: 0)
        let next = CircleOfFifths.next(aMinor)
        XCTAssertEqual(next.mode, .minor)
        XCTAssertEqual(next.tonic.name, "E")
    }

    func testDistanceShortestPath() {
        let c = Key.major(circlePosition: 0)
        XCTAssertEqual(CircleOfFifths.distance(from: c, to: Key.major(circlePosition: 1)), 1)
        // C to F (one seat anticlockwise) is also distance 1 by the short way.
        XCTAssertEqual(CircleOfFifths.distance(from: c, to: Key.major(circlePosition: -1)), 1)
        // C to F♯ (the tritone, opposite the wheel) is the maximum, 6.
        XCTAssertEqual(CircleOfFifths.distance(from: c, to: Key.major(circlePosition: 6)), 6)
        XCTAssertEqual(CircleOfFifths.distance(from: c, to: c), 0)
    }
}
