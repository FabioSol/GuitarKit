//
//  TuningSessionTests.swift
//  GuitarKitTests
//
//  Behavioral tests for the targeted-tuning state machine. We script sequences
//  of (frequency, time) the way real playing would arrive and assert the
//  machine's externally-visible behavior: which string it picks, the deviation
//  and direction, the hold-to-latch timing, tap-to-lock override, and the
//  all-green completion — exactly the PRD's "feed scripted pitch sequences"
//  testing decision.
//

import XCTest
@testable import GuitarKit

final class TuningSessionTests: XCTestCase {

    // A standard-guitar session built the same way the app builds it.
    private func makeSession(
        tolerance: TuningTolerance = .standard
    ) -> TuningSession {
        let targets = PitchCalculator().targets(for: BuiltInTuning.standardGuitar)
        return TuningSession(targets: targets, tolerance: tolerance)
    }

    // Exact equal-tempered frequency of a note at A=440 (for scripting input).
    private func hz(_ pitchClass: PitchClass, _ octave: Int) -> Double {
        PitchCalculator().frequency(of: Note(pitchClass: pitchClass, octave: octave))
    }

    // MARK: - Auto-detect nearest string + deviation

    func test_playingAString_autoSelectsNearestString() {
        var session = makeSession()
        // Play an A2 (the 5th string, index 1 in EADGBE order).
        session.update(detectedFrequency: hz(.a, 2), at: 0)
        XCTAssertEqual(session.activeStringIndex, 1)
    }

    func test_deviation_isSharp_whenAboveTarget() {
        var session = makeSession()
        // 10 cents above low E (E2).
        let sharpE = hz(.e, 2) * pow(2.0, 10.0 / 1200.0)
        session.update(detectedFrequency: sharpE, at: 0)
        XCTAssertEqual(session.activeStringIndex, 0)
        XCTAssertEqual(session.deviationCents ?? .nan, 10, accuracy: 0.1)
        XCTAssertEqual(session.zone, .sharp)
    }

    func test_deviation_isFlat_whenBelowTarget() {
        var session = makeSession()
        let flatA = hz(.a, 2) * pow(2.0, -8.0 / 1200.0)
        session.update(detectedFrequency: flatA, at: 0)
        XCTAssertEqual(session.zone, .flat)
        XCTAssertLessThan(session.deviationCents ?? 0, 0)
    }

    func test_perfectZone_withinOneCent() {
        var session = makeSession()
        session.update(detectedFrequency: hz(.d, 3), at: 0)   // dead-on D3
        XCTAssertEqual(session.zone, .perfect)
    }

    // MARK: - Hold-to-confirm latching

    func test_inTunePitch_doesNotLatchImmediately() {
        var session = makeSession()
        // In tune, but only for an instant — must not latch yet.
        session.update(detectedFrequency: hz(.e, 2), at: 0)
        XCTAssertFalse(session.isLatched(0))
    }

    func test_holdingInTune_forHoldDuration_latches() {
        var session = makeSession()  // holdDuration = 0.7
        let e = hz(.e, 2)
        session.update(detectedFrequency: e, at: 0.0)   // enters tolerance
        session.update(detectedFrequency: e, at: 0.4)   // still holding
        XCTAssertFalse(session.isLatched(0))
        session.update(detectedFrequency: e, at: 0.7)   // hold satisfied → latch
        XCTAssertTrue(session.isLatched(0))
        XCTAssertEqual(session.justLatchedStringIndex, 0)
    }

    func test_driftingOutOfTune_resetsTheHold() {
        var session = makeSession()
        let e = hz(.e, 2)
        let wayFlat = e * pow(2.0, -30.0 / 1200.0)  // 30¢ flat, outside tolerance
        session.update(detectedFrequency: e, at: 0.0)        // start hold
        session.update(detectedFrequency: wayFlat, at: 0.4)  // drift out → reset
        session.update(detectedFrequency: e, at: 0.8)        // re-enter (hold restarts)
        // Only 0.0s of continuous hold since re-entry → not latched yet.
        XCTAssertFalse(session.isLatched(0))
        session.update(detectedFrequency: e, at: 1.5)        // 0.7s after re-entry
        XCTAssertTrue(session.isLatched(0))
    }

    func test_signalDropout_resetsTheHold() {
        var session = makeSession()
        let e = hz(.e, 2)
        session.update(detectedFrequency: e, at: 0.0)     // start hold
        session.update(detectedFrequency: nil, at: 0.4)   // silence → reset hold
        session.update(detectedFrequency: e, at: 0.8)     // restart
        XCTAssertFalse(session.isLatched(0))
        session.update(detectedFrequency: e, at: 1.5)
        XCTAssertTrue(session.isLatched(0))
    }

    func test_latchedString_staysLatched_evenIfDetunedLater() {
        var session = makeSession()
        let e = hz(.e, 2)
        session.update(detectedFrequency: e, at: 0.0)
        session.update(detectedFrequency: e, at: 0.7)     // latched
        XCTAssertTrue(session.isLatched(0))
        // Now play it wildly out of tune again — it must remain latched.
        session.update(detectedFrequency: e * pow(2.0, -50.0 / 1200.0), at: 1.0)
        XCTAssertTrue(session.isLatched(0))
    }

    // MARK: - Tap-to-lock override

    func test_manualLock_targetsThatString_evenWhenNearAnother() {
        var session = makeSession()
        // Lock onto the high E (index 5) but play something near low E.
        session.lock(toStringIndex: 5)
        XCTAssertTrue(session.isManuallyLocked)
        session.update(detectedFrequency: hz(.e, 2), at: 0)
        // Despite the pitch being nearest the LOW E, the active string stays the
        // locked high E — and the deviation is measured against it.
        XCTAssertEqual(session.activeStringIndex, 5)
        XCTAssertNotEqual(session.deviationCents ?? 0, 0, accuracy: 0.0001) // far off
    }

    func test_manualLock_letsAWildlyOutOfTuneStringBeTuned() {
        var session = makeSession()
        session.lock(toStringIndex: 0)  // low E
        // A string a whole semitone flat would auto-match the wrong target; the
        // lock keeps us on string 0 while we bring it up and latch it.
        let onPitch = hz(.e, 2)
        session.update(detectedFrequency: onPitch, at: 0.0)
        session.update(detectedFrequency: onPitch, at: 0.7)
        XCTAssertTrue(session.isLatched(0))
        // Latching clears the manual lock so the player flows onward.
        XCTAssertFalse(session.isManuallyLocked)
    }

    func test_lock_outOfRangeIndex_isIgnored() {
        var session = makeSession()
        session.lock(toStringIndex: 99)
        XCTAssertFalse(session.isManuallyLocked)
        XCTAssertNil(session.activeStringIndex)
    }

    // MARK: - Suggestion + completion

    func test_suggestedString_isFirstUnlatched() {
        var session = makeSession()
        XCTAssertEqual(session.suggestedStringIndex, 0)
        // Latch string 0.
        let e = hz(.e, 2)
        session.update(detectedFrequency: e, at: 0.0)
        session.update(detectedFrequency: e, at: 0.7)
        XCTAssertEqual(session.suggestedStringIndex, 1)
    }

    func test_allStringsLatched_reachesCompletion() {
        var session = makeSession()
        let notes = BuiltInTuning.standardGuitar
        // Give each string its own 2-second window, computed from the index so
        // timestamps don't accumulate floating-point drift across the loop. The
        // hold update sits a full second in — comfortably past the 0.7s hold.
        for (i, note) in notes.enumerated() {
            let base = Double(i) * 2.0
            let f = PitchCalculator().frequency(of: note)
            session.update(detectedFrequency: f, at: base)         // enter tolerance
            session.update(detectedFrequency: f, at: base + 1.0)   // hold → latch
            session.update(detectedFrequency: nil, at: base + 1.5) // silence between strings
        }
        XCTAssertTrue(session.isComplete)
        XCTAssertNil(session.suggestedStringIndex)
    }

    func test_notComplete_untilEveryStringLatched() {
        var session = makeSession()
        let e = hz(.e, 2)
        session.update(detectedFrequency: e, at: 0.0)
        session.update(detectedFrequency: e, at: 0.7)
        XCTAssertTrue(session.isLatched(0))
        XCTAssertFalse(session.isComplete)
    }

    // MARK: - justLatched is a one-shot event

    func test_justLatched_isOnlySetOnTheLatchingUpdate() {
        var session = makeSession()
        let e = hz(.e, 2)
        session.update(detectedFrequency: e, at: 0.0)
        XCTAssertNil(session.justLatchedStringIndex)
        session.update(detectedFrequency: e, at: 0.7)
        XCTAssertEqual(session.justLatchedStringIndex, 0)   // fires once
        session.update(detectedFrequency: e, at: 1.0)
        XCTAssertNil(session.justLatchedStringIndex)         // and is cleared
    }
}
