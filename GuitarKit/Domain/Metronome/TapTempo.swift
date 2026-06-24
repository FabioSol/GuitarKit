//
//  TapTempo.swift
//  GuitarKit
//
//  The PURE "tap a button in time, get a tempo" math behind the metronome's
//  tap-tempo feature. No UI, no audio, no clock of its own — you hand it the
//  TIMESTAMP of each tap and it tells you the implied BPM. That separation is
//  deliberate (same idea as `MetronomeSequencer`): keeping this a plain
//  Foundation value type means we can unit-test it deterministically by feeding
//  in fake timestamps, with NO main actor, NO real wall-clock, and NO flakiness.
//
//  HOW TAP TEMPO WORKS (the idea):
//  If you tap a button twice exactly half a second apart, the gap between taps
//  is 0.5 s — and 0.5 s per beat is 120 beats per minute (60 / 0.5 = 120). So:
//
//      bpm = 60 / (seconds between two taps)
//
//  The FIRST tap can't give us a tempo on its own (there's no gap yet), so we
//  just remember its time and wait for the next. From the second tap onward we
//  have an interval and can produce a BPM. To smooth out human imprecision we
//  AVERAGE the recent intervals rather than trusting only the last one.
//
//  RESET ON A LONG GAP:
//  If you walk away and tap again much later, that huge gap isn't a tempo — it's
//  a new attempt. So if the gap since the previous tap exceeds `resetGap`
//  (default 2 s, i.e. slower than 30 BPM), we throw away the old taps and start
//  a fresh series from this tap.
//

import Foundation

/// Turns a series of tap timestamps into a BPM estimate.
///
/// A `struct` (value type) on purpose: it holds only a little state (the recent
/// tap times) and has no identity to share, so value semantics are the natural,
/// safe fit — and value types are trivially testable off the main actor. You
/// keep one instance and call `mutating func register(at:)` each time the user
/// taps; it returns the current best BPM estimate (or `nil` while it still only
/// has a single tap and can't yet measure an interval).
struct TapTempo {

    // MARK: - Tuning constants

    /// The slowest/fastest tempo we'll ever report. Matches the metronome face's
    /// 30–300 BPM range so a frantic or sluggish tap can't push the dial out of
    /// bounds. Anything we compute is clamped into this range before returning.
    static let minBPM: Double = 30
    static let maxBPM: Double = 300

    /// If the gap between two consecutive taps is LONGER than this, we treat the
    /// new tap as the start of a fresh series (the user paused and started over).
    /// 2 s corresponds to 30 BPM, so any in-range tempo never trips this.
    let resetGap: TimeInterval

    /// How many of the MOST RECENT intervals we average over. A small window
    /// keeps the estimate responsive when the user changes their tapping speed,
    /// while still smoothing out the jitter of any single tap. (An "interval" is
    /// the gap between two adjacent taps, so N taps give N−1 intervals.)
    let maxIntervals: Int

    // MARK: - State

    /// The timestamps of the recent taps that make up the current series, oldest
    /// first. We keep at most `maxIntervals + 1` of them (that many taps yields
    /// `maxIntervals` gaps to average). Cleared whenever a long gap resets us.
    private var taps: [TimeInterval] = []

    // MARK: - Init

    /// - Parameters:
    ///   - resetGap: gap (seconds) above which a new tap starts a fresh series.
    ///   - maxIntervals: how many recent gaps to average. Both have sensible
    ///     defaults; they're parameters mainly so the tests can pin them down.
    init(resetGap: TimeInterval = 2.0, maxIntervals: Int = 4) {
        self.resetGap = resetGap
        // Never less than 1 interval, otherwise we could never produce a tempo.
        self.maxIntervals = max(1, maxIntervals)
    }

    // MARK: - Tapping

    /// Record a tap that happened at time `now` (in seconds; any monotonic clock
    /// works, e.g. `Date().timeIntervalSinceReferenceDate` or
    /// `ProcessInfo.processInfo.systemUptime`). Returns the current BPM estimate,
    /// or `nil` if there isn't yet enough information (only one tap so far, or a
    /// reset just happened) to measure an interval.
    ///
    /// `mutating` because each tap updates the remembered series — the natural,
    /// readable way to model "this object accumulates taps over time."
    mutating func register(at now: TimeInterval) -> Double? {
        // Decide whether this tap continues the current series or starts a new
        // one. It starts fresh if we have no previous tap, or if the gap since
        // the last tap is too long to be a real beat.
        if let last = taps.last, now - last <= resetGap {
            taps.append(now)
        } else {
            // Either the very first tap, or a long pause: begin again from here.
            taps = [now]
        }

        // Keep only the newest `maxIntervals + 1` taps so the average always
        // reflects the user's CURRENT tapping speed, not stale early taps.
        let maxTaps = maxIntervals + 1
        if taps.count > maxTaps {
            taps.removeFirst(taps.count - maxTaps)
        }

        return currentBPM
    }

    /// Forget the current series. Call this if the UI wants to abandon an
    /// in-progress tap sequence (e.g. the user stopped the metronome) so the next
    /// tap is treated as a brand-new first tap.
    mutating func reset() {
        taps.removeAll()
    }

    // MARK: - Derived

    /// The BPM implied by the remembered taps, or `nil` if fewer than two taps
    /// exist (no interval to measure yet). The result is always clamped into
    /// `minBPM...maxBPM`.
    var currentBPM: Double? {
        // Need at least two taps for one interval.
        guard taps.count >= 2 else { return nil }

        // Build the list of gaps between adjacent taps. `zip(taps, taps[1...])`
        // pairs each tap with the one after it; subtracting gives each interval.
        var intervals: [TimeInterval] = []
        intervals.reserveCapacity(taps.count - 1)
        for i in 1..<taps.count {
            intervals.append(taps[i] - taps[i - 1])
        }

        // Average the intervals → the typical seconds-per-beat the user is
        // tapping. Averaging (rather than using only the last gap) smooths out
        // the unavoidable wobble in human timing.
        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)

        // A zero/negative average can't happen with strictly increasing
        // timestamps, but guard anyway so we never divide by zero.
        guard averageInterval > 0 else { return nil }

        // seconds-per-beat → BPM, then clamp into the metronome's range.
        let bpm = 60.0 / averageInterval
        return min(max(bpm, Self.minBPM), Self.maxBPM)
    }
}
