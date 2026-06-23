//
//  PitchSmootherTests.swift
//  GuitarKitTests
//
//  Tests for the median + EMA smoothing stage. The behaviors that matter:
//  steady input stays steady, a lone outlier (an octave-jump glitch) is
//  rejected by the median, and reset clears history.
//

import XCTest
@testable import GuitarKit

final class PitchSmootherTests: XCTestCase {

    func test_steadyInput_convergesToThatValue() {
        var smoother = PitchSmoother()
        var output: Float = 0
        // Feed the same frequency repeatedly; the EMA should settle on it.
        for _ in 0..<20 { output = smoother.push(110) }
        XCTAssertEqual(output, 110, accuracy: 0.01)
    }

    func test_firstReading_isNotDraggedFromZero() {
        // With no prior history the very first output should equal the input,
        // not start at 0 and crawl up.
        var smoother = PitchSmoother()
        XCTAssertEqual(smoother.push(82.41), 82.41, accuracy: 0.01)
    }

    func test_singleOutlier_isRejectedByMedian() {
        var smoother = PitchSmoother(windowSize: 5)
        // Establish a steady 100 Hz reading.
        for _ in 0..<5 { _ = smoother.push(100) }
        // One wild octave-up glitch arrives. The window is {100,100,100,100,200};
        // its median is still 100, so the output must barely move.
        let output = smoother.push(200)
        XCTAssertEqual(output, 100, accuracy: 1.0)
    }

    func test_reset_clearsHistory() {
        var smoother = PitchSmoother()
        for _ in 0..<5 { _ = smoother.push(440) }
        smoother.reset()
        // After reset the next reading seeds fresh (equals its input) instead of
        // gliding from the old 440.
        XCTAssertEqual(smoother.push(110), 110, accuracy: 0.01)
    }

    func test_sustainedShift_eventuallyTracksNewValue() {
        // A genuine pitch change (not a glitch) should be followed once it
        // persists past the median window.
        var smoother = PitchSmoother(windowSize: 5)
        for _ in 0..<5 { _ = smoother.push(100) }
        var output: Float = 0
        for _ in 0..<20 { output = smoother.push(150) }
        XCTAssertEqual(output, 150, accuracy: 0.5)
    }
}
