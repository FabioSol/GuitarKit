//
//  PitchContinuityTests.swift
//  GuitarKitTests
//
//  The temporal hygiene state machine, driven with scripted frame sequences.
//  Frames arrive graded — `.strong` (passed the onset gates), `.weak` (passed
//  only the relaxed sustain gates) or nil (rejected) — and the filter answers:
//  publish, hold back, stay silent, or declare a dropout (→ the caller drops
//  smoothing history).
//

import XCTest
@testable import GuitarKit

final class PitchContinuityTests: XCTestCase {

    // MARK: - Onset confirmation (isolated false accepts must not publish)

    func test_firstAcceptedFrame_isHeldBack_notPublished() {
        var c = PitchContinuity()
        XCTAssertEqual(c.ingest(.strong(220)), .hold,
                       "a lone frame after silence is a candidate, not a reading")
    }

    func test_secondAgreeingFrame_confirms_andPublishesBoth() {
        var c = PitchContinuity()
        _ = c.ingest(.strong(220))
        // 221 Hz is ~8 cents from 220 — same note, trivially inside 100¢.
        XCTAssertEqual(c.ingest(.strong(221)), .track([220, 221]),
                       "candidate + confirming frame publish together, in order")
    }

    func test_disagreeingSecondFrame_replacesCandidate() {
        var c = PitchContinuity()
        _ = c.ingest(.strong(220))
        // 330 Hz is ~700 cents away — one of the two was junk. Hold again…
        XCTAssertEqual(c.ingest(.strong(330)), .hold)
        // …and the NEWER frame is the live candidate: agreeing with it confirms.
        XCTAssertEqual(c.ingest(.strong(331)), .track([330, 331]))
    }

    func test_rejectBetweenAccepts_killsTheCandidate() {
        var c = PitchContinuity()
        _ = c.ingest(.strong(220))     // candidate
        _ = c.ingest(nil)              // broken run — candidate dies
        XCTAssertEqual(c.ingest(.strong(220)), .hold,
                       "confirmation requires two CONSECUTIVE agreeing frames")
    }

    func test_isolatedNoiseAccepts_neverPublish() {
        var c = PitchContinuity()
        // The exact between-plucks pattern: stray accepts at random pitches,
        // separated by rejected frames. None may reach the screen.
        for frequency in [Float(313), 87, 542, 129] {
            XCTAssertEqual(c.ingest(.strong(frequency)), .hold)
            _ = c.ingest(nil)
        }
    }

    // MARK: - Mid-note behavior (confirmed notes flow freely)

    private func confirmedAt220() -> PitchContinuity {
        var c = PitchContinuity()
        _ = c.ingest(.strong(220))
        _ = c.ingest(.strong(220))
        return c
    }

    func test_whileTracking_framesPublishDirectly() {
        var c = confirmedAt220()
        XCTAssertEqual(c.ingest(.strong(222)), .track([222]))
    }

    func test_singleRejectMidNote_staysSilent_keepsTracking() {
        var c = confirmedAt220()
        XCTAssertEqual(c.ingest(nil), .silence,
                       "one marginal buffer must not end the note")
        XCTAssertEqual(c.ingest(.strong(220)), .track([220]),
                       "the note resumes without re-confirmation")
    }

    // MARK: - Sustain hysteresis (weak frames extend the tail, never start one)

    func test_weakFrameNearTrackedPitch_extendsTheNote() {
        var c = confirmedAt220()
        // The decaying tail: below the onset gates, but on-pitch. Stays live.
        XCTAssertEqual(c.ingest(.weak(221)), .track([221]))
        XCTAssertEqual(c.ingest(.weak(220)), .track([220]),
                       "a chain of on-pitch weak frames rides the tail down")
    }

    func test_weakFrameFarFromTrackedPitch_isRejected() {
        var c = confirmedAt220()
        // 330 Hz is ~700¢ from the anchor — marginal AND off-pitch is noise.
        XCTAssertEqual(c.ingest(.weak(330)), .silence)
        XCTAssertEqual(c.ingest(.weak(330)), .dropout,
                       "off-pitch weak frames count toward the dropout streak")
    }

    func test_weakFrame_cannotStartANote() {
        var c = PitchContinuity()
        XCTAssertEqual(c.ingest(.weak(220)), .silence,
                       "while dormant, weak evidence is noise")
        XCTAssertEqual(c.ingest(.weak(220)), .silence,
                       "no matter how often it repeats")
    }

    func test_weakFrame_cannotConfirmACandidate() {
        var c = PitchContinuity()
        _ = c.ingest(.strong(220))     // candidate
        XCTAssertEqual(c.ingest(.weak(220)), .silence,
                       "onset demands strong evidence — the weak frame kills the run")
        XCTAssertEqual(c.ingest(.strong(220)), .hold,
                       "so the next strong frame starts a fresh candidate")
    }

    func test_afterDropout_weakFrames_cannotRestartTheTail() {
        var c = confirmedAt220()
        _ = c.ingest(nil)
        _ = c.ingest(nil)              // dropout — the note is over
        XCTAssertEqual(c.ingest(.weak(220)), .silence,
                       "once the note ended, only strong evidence starts a new one")
    }

    // MARK: - Dropout (consecutive rejects end the note, once)

    func test_consecutiveRejects_declareDropout_onTheEdge() {
        var c = confirmedAt220()
        XCTAssertEqual(c.ingest(nil), .silence)   // streak 1: allowance
        XCTAssertEqual(c.ingest(nil), .dropout,   // streak 2: note over
                       "the history-drop signal fires exactly on the edge")
        XCTAssertEqual(c.ingest(nil), .silence,
                       "further rejects are plain silence — dropout is one-shot")
    }

    func test_afterDropout_newNoteNeedsConfirmationAgain() {
        var c = confirmedAt220()
        _ = c.ingest(nil)
        _ = c.ingest(nil)                          // dropout
        XCTAssertEqual(c.ingest(.strong(440)), .hold,
                       "post-dropout, the first frame is a candidate again")
        XCTAssertEqual(c.ingest(.strong(440)), .track([440, 440]))
    }

    // MARK: - Reset

    func test_reset_returnsToColdStart() {
        var c = confirmedAt220()
        c.reset()
        XCTAssertEqual(c.ingest(.strong(220)), .hold,
                       "after reset, tracking must be re-confirmed from scratch")
    }

    func test_nonPositiveFrequency_isTreatedAsReject() {
        var c = confirmedAt220()
        XCTAssertEqual(c.ingest(.strong(0)), .silence)
        XCTAssertEqual(c.ingest(.weak(-1)), .dropout)
    }
}
