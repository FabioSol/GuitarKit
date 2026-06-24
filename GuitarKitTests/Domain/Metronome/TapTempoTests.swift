//
//  TapTempoTests.swift
//  GuitarKitTests
//
//  Tests for the pure tap-tempo math. The behaviors that matter: two taps a known
//  interval apart give the right BPM, a long pause resets the series, a steady
//  stream of taps averages to the right tempo, and the result is clamped to
//  30–300. Because `TapTempo` is plain Foundation we can feed it fake timestamps
//  and assert deterministically — no real clock, no main actor, no flakiness.
//

import XCTest
@testable import GuitarKit

final class TapTempoTests: XCTestCase {

    // MARK: - Basic interval → BPM

    func test_firstTap_yieldsNoTempo() {
        var tt = TapTempo()
        // One tap can't define an interval, so there's no BPM yet.
        XCTAssertNil(tt.register(at: 0.0))
    }

    func test_twoTaps_halfSecondApart_is120BPM() {
        var tt = TapTempo()
        XCTAssertNil(tt.register(at: 0.0))           // first tap: anchor only
        let bpm = tt.register(at: 0.5)               // 0.5 s gap → 60/0.5 = 120
        XCTAssertEqual(bpm ?? 0, 120, accuracy: 0.0001)
    }

    func test_twoTaps_oneSecondApart_is60BPM() {
        var tt = TapTempo()
        _ = tt.register(at: 10.0)
        let bpm = tt.register(at: 11.0)              // 1 s gap → 60 BPM
        XCTAssertEqual(bpm ?? 0, 60, accuracy: 0.0001)
    }

    // MARK: - Averaging a steady stream

    func test_steadyStream_averagesToTempo() {
        // Taps every 0.5 s should settle on 120 BPM regardless of how many.
        var tt = TapTempo()
        var last: Double?
        for i in 0...6 {
            last = tt.register(at: Double(i) * 0.5)
        }
        XCTAssertEqual(last ?? 0, 120, accuracy: 0.0001)
    }

    func test_averaging_smoothsWobble() {
        // Intervals 0.5, 0.6, 0.4 average to 0.5 s → 120 BPM, even though no
        // single gap is exactly 0.5. (maxIntervals default 4 keeps all three.)
        var tt = TapTempo()
        _ = tt.register(at: 0.0)
        _ = tt.register(at: 0.5)   // gap 0.5
        _ = tt.register(at: 1.1)   // gap 0.6
        let bpm = tt.register(at: 1.5)   // gap 0.4 → avg 0.5 → 120
        XCTAssertEqual(bpm ?? 0, 120, accuracy: 0.5)
    }

    // MARK: - Reset on a long gap

    func test_longGap_resetsSeries() {
        var tt = TapTempo()
        _ = tt.register(at: 0.0)
        _ = tt.register(at: 0.5)        // establishes 120 BPM
        // A gap well beyond the 2 s reset threshold: this tap starts over, so the
        // huge gap is NOT interpreted as a (very slow) tempo — we get nil again.
        XCTAssertNil(tt.register(at: 10.0))
        // And the next tap measures only from the fresh start.
        let bpm = tt.register(at: 10.5)   // 0.5 s after the reset tap → 120
        XCTAssertEqual(bpm ?? 0, 120, accuracy: 0.0001)
    }

    func test_gapExactlyAtThreshold_doesNotReset() {
        // A gap equal to `resetGap` is allowed (<=), so the series continues.
        var tt = TapTempo(resetGap: 2.0)
        _ = tt.register(at: 0.0)
        let bpm = tt.register(at: 2.0)   // 2 s gap → 30 BPM, not a reset
        XCTAssertEqual(bpm ?? 0, 30, accuracy: 0.0001)
    }

    // MARK: - Clamping to 30–300

    func test_veryFastTaps_clampAt300() {
        // 0.1 s apart would be 600 BPM; clamp to the 300 ceiling.
        var tt = TapTempo()
        _ = tt.register(at: 0.0)
        let bpm = tt.register(at: 0.1)
        XCTAssertEqual(bpm ?? 0, 300, accuracy: 0.0001)
    }

    func test_slowTaps_clampAt30() {
        // 1.5 s apart is 40 BPM (in range); but push to a 3 s gap to test the
        // floor. A 3 s gap would reset, so use a wider resetGap for this test so
        // the slow interval survives to be clamped.
        var tt = TapTempo(resetGap: 10.0)
        _ = tt.register(at: 0.0)
        let bpm = tt.register(at: 3.0)   // 3 s → 20 BPM → clamp up to 30
        XCTAssertEqual(bpm ?? 0, 30, accuracy: 0.0001)
    }

    // MARK: - Explicit reset

    func test_reset_clearsSeries() {
        var tt = TapTempo()
        _ = tt.register(at: 0.0)
        _ = tt.register(at: 0.5)
        tt.reset()
        // After reset the next tap is a fresh "first tap" → no tempo yet.
        XCTAssertNil(tt.register(at: 1.0))
    }
}
