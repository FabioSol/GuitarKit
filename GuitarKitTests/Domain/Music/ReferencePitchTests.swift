//
//  ReferencePitchTests.swift
//  GuitarKitTests
//
//  Behavioral tests for reference-pitch calibration clamping (A=415...466).
//

import XCTest
@testable import GuitarKit

final class ReferencePitchTests: XCTestCase {

    func test_standard_is440() {
        XCTAssertEqual(ReferencePitch.standard.hertz, 440)
    }

    func test_acceptsValuesWithinRange() {
        XCTAssertEqual(ReferencePitch(hertz: 415).hertz, 415)
        XCTAssertEqual(ReferencePitch(hertz: 432).hertz, 432)
        XCTAssertEqual(ReferencePitch(hertz: 442).hertz, 442)
        XCTAssertEqual(ReferencePitch(hertz: 466).hertz, 466)
    }

    func test_clampsBelowMinimum() {
        XCTAssertEqual(ReferencePitch(hertz: 400).hertz, ReferencePitch.minHz)
        XCTAssertEqual(ReferencePitch.minHz, 415)
    }

    func test_clampsAboveMaximum() {
        XCTAssertEqual(ReferencePitch(hertz: 500).hertz, ReferencePitch.maxHz)
        XCTAssertEqual(ReferencePitch.maxHz, 466)
    }

    func test_nonFiniteInput_fallsBackToConcertPitch() {
        // NaN/±Inf can't be clamped meaningfully; the invariant "always a finite,
        // in-range value" must still hold.
        XCTAssertEqual(ReferencePitch(hertz: .nan).hertz, 440)
        XCTAssertEqual(ReferencePitch(hertz: .infinity).hertz, 440)
        XCTAssertEqual(ReferencePitch(hertz: -.infinity).hertz, 440)
        XCTAssertTrue(ReferencePitch(hertz: .nan).hertz.isFinite)
    }
}
