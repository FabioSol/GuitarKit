//
//  TuningFeedbackTests.swift
//  GuitarKitTests
//
//  Exhaustive tests for the pure zone-transition → haptic-event rule. These pin
//  down exactly when a tick fires so the haptics never "machine-gun" while a
//  string is held in tune, and never fire on the way back out.
//

import XCTest
@testable import GuitarKit

final class TuningFeedbackTests: XCTestCase {

    // MARK: - Perfect tick (arriving at ±1¢)

    func test_entersPerfect_fromInTune_firesPerfect() {
        XCTAssertEqual(tuningFeedbackEvent(from: .inTune, to: .perfect), .enteredPerfect)
    }

    func test_entersPerfect_fromFlat_firesPerfect() {
        XCTAssertEqual(tuningFeedbackEvent(from: .flat, to: .perfect), .enteredPerfect)
    }

    func test_entersPerfect_fromColdStart_firesPerfect() {
        XCTAssertEqual(tuningFeedbackEvent(from: nil, to: .perfect), .enteredPerfect)
    }

    func test_stayingPerfect_firesNothing() {
        XCTAssertNil(tuningFeedbackEvent(from: .perfect, to: .perfect))
    }

    // MARK: - In-tune tick (arriving at ±3¢)

    func test_entersInTune_fromSharp_firesInTune() {
        XCTAssertEqual(tuningFeedbackEvent(from: .sharp, to: .inTune), .enteredInTune)
    }

    func test_entersInTune_fromColdStart_firesInTune() {
        XCTAssertEqual(tuningFeedbackEvent(from: nil, to: .inTune), .enteredInTune)
    }

    func test_stayingInTune_firesNothing() {
        XCTAssertNil(tuningFeedbackEvent(from: .inTune, to: .inTune))
    }

    func test_easingFromPerfectToInTune_isSilent() {
        // Drifting out of perfect back into the wider in-tune band is NOT an
        // arrival — it must not fire the in-tune tick.
        XCTAssertNil(tuningFeedbackEvent(from: .perfect, to: .inTune))
    }

    // MARK: - Out of tune / dropout

    func test_movingToSharp_firesNothing() {
        XCTAssertNil(tuningFeedbackEvent(from: .inTune, to: .sharp))
    }

    func test_movingToFlat_firesNothing() {
        XCTAssertNil(tuningFeedbackEvent(from: .perfect, to: .flat))
    }

    func test_signalDropout_firesNothing() {
        XCTAssertNil(tuningFeedbackEvent(from: .perfect, to: nil))
    }

    func test_noReadingEither_firesNothing() {
        XCTAssertNil(tuningFeedbackEvent(from: nil, to: nil))
    }
}
