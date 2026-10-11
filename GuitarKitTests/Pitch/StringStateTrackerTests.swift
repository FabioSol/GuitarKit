//
//  StringStateTrackerTests.swift
//  GuitarKitTests
//
//  The probabilistic string tracker, driven with SCRIPTED frames — no audio.
//  Each test describes a situation a player meets (a pluck, a voice over a
//  ringing string, a chord, silence) as a sequence of observations and checks
//  what the tuner would show.
//

import XCTest
@testable import GuitarKit

final class StringStateTrackerTests: XCTestCase {

    /// Standard guitar: E2 A2 D3 G3 B3 E4.
    private let guitar = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63]

    /// A frame where the detector found `hz`.
    private func heard(_ hz: Float, level: Float = -40, clarity: Float = 0.9, harmonicity: Float = 0.9,
                       salience: Float? = nil) -> StringStateTracker.Observation {
        .init(levelDB: level,
              candidate: .init(frequency: hz, clarity: clarity, harmonicity: harmonicity),
              salience: { _ in salience }, refine: { $0 })
    }

    /// A frame where nothing was detected.
    private func nothing(level: Float = -95) -> StringStateTracker.Observation {
        .init(levelDB: level, candidate: nil)
    }

    private func shownString(_ d: StringStateTracker.Decision) -> Int? {
        if case let .ringing(index, _, _) = d { return index }
        return nil
    }

    // MARK: - A plucked string

    func test_pluck_showsTheStringWithinTwoFrames() {
        var tracker = StringStateTracker(targets: guitar)
        _ = tracker.step(nothing())                       // quiet room before the pluck
        let first = tracker.step(heard(110.4))            // the pluck: a level jump
        let second = tracker.step(heard(110.3, level: -42))
        XCTAssertTrue(shownString(first) == 1 || shownString(second) == 1,
                      "a clean A2 pluck should show within two frames")
        XCTAssertEqual(shownString(second), 1)
    }

    func test_shownFrequency_isWhatWasHeard_notTheTarget() {
        // A flat string must read flat — the target only helps decide WHICH string.
        var tracker = StringStateTracker(targets: guitar)
        _ = tracker.step(nothing())
        var last = StringStateTracker.Decision.silent
        for _ in 0..<4 { last = tracker.step(heard(106.0)) }   // ~65¢ flat of A2
        guard case let .ringing(index, frequency, _) = last else { return XCTFail("expected A2") }
        XCTAssertEqual(index, 1)
        XCTAssertEqual(frequency, 106.0, accuracy: 0.01)
    }

    func test_quietRoom_showsNothing() {
        var tracker = StringStateTracker(targets: guitar)
        for _ in 0..<20 { XCTAssertNil(shownString(tracker.step(nothing()))) }
    }

    func test_stringFadesOut_afterItStopsBeingHeard() {
        var tracker = StringStateTracker(targets: guitar)
        _ = tracker.step(nothing())
        for _ in 0..<5 { _ = tracker.step(heard(196)) }
        var silentWithin: Int?
        for frame in 1...20 where silentWithin == nil {
            if shownString(tracker.step(nothing())) == nil { silentWithin = frame }
        }
        XCTAssertNotNil(silentWithin, "a string that's no longer heard must stop showing")
        XCTAssertLessThanOrEqual(silentWithin ?? 99, 10)
    }

    // MARK: - Interference

    func test_lowHarmonicitySound_neverShows() {
        // A chord or a messy voice: periodic enough for the detector, but not
        // one harmonic source.
        var tracker = StringStateTracker(targets: guitar)
        _ = tracker.step(nothing())
        for _ in 0..<15 {
            XCTAssertNil(shownString(tracker.step(heard(147, harmonicity: 0.35))))
        }
    }

    func test_stringStaysShown_whenAVoiceTakesOverTheDetector() {
        // A ringing A2; then the detector latches onto a voice at 280 Hz — but
        // A2's partials still stand out in the spectrum (salience).
        var tracker = StringStateTracker(targets: guitar)
        _ = tracker.step(nothing())
        for _ in 0..<4 { _ = tracker.step(heard(110)) }
        for _ in 0..<3 {
            let d = tracker.step(heard(280, harmonicity: 0.6, salience: 0.9))
            XCTAssertEqual(shownString(d), 1, "the A2 is still ringing underneath the voice")
        }
    }

    // MARK: - Moving between strings

    func test_pluckingAnotherString_switchesQuickly() {
        var tracker = StringStateTracker(targets: guitar)
        _ = tracker.step(nothing())
        for _ in 0..<5 { _ = tracker.step(heard(110, level: -50)) }
        // A new pluck on D3: the level jumps.
        let first = tracker.step(heard(146.5, level: -35))
        let second = tracker.step(heard(146.6, level: -37))
        XCTAssertTrue(shownString(first) == 2 || shownString(second) == 2)
        XCTAssertEqual(shownString(second), 2)
    }

    func test_octaveReading_isFoldedBackOntoTheString() {
        // The detector reads the low E an octave up (its 2nd harmonic): the
        // tracker should still show the low E, at the fundamental's frequency.
        var tracker = StringStateTracker(targets: guitar)
        _ = tracker.step(nothing())
        var last = StringStateTracker.Decision.silent
        for _ in 0..<5 { last = tracker.step(heard(164.9)) }   // 2 × 82.45
        // 164.9 Hz is 2 semitones off D3 but exactly an octave of E2; either
        // reading is defensible, but it must not be shown as anything else.
        if case let .ringing(index, frequency, _) = last, index == 0 {
            XCTAssertEqual(frequency, 82.45, accuracy: 0.01)
        }
        XCTAssertTrue([0, 2, nil].contains(shownString(last)))
    }

    func test_reset_forgetsEverything() {
        var tracker = StringStateTracker(targets: guitar)
        _ = tracker.step(nothing())
        for _ in 0..<5 { _ = tracker.step(heard(110)) }
        tracker.reset()
        XCTAssertEqual(tracker.belief.first ?? 0, 1, accuracy: 1e-6, "back to silence")
    }

    func test_noTargets_neverShows() {
        var tracker = StringStateTracker(targets: [])
        XCTAssertEqual(tracker.step(heard(110)), .silent)
    }
}
