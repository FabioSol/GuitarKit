//
//  PitchSmoother.swift
//  GuitarKit
//
//  Cleans up a stream of raw per-buffer frequency estimates into a steady value
//  the UI can display without flicker. Pure value logic — no audio, no UI — so
//  it's unit-testable on its own.
//
//  TWO STAGES, EACH FIXING A DIFFERENT PROBLEM:
//
//   1. MEDIAN over a small window — kills *outliers*. Even a good detector
//      occasionally reports a one-off octave jump (e.g. one 165 Hz reading in a
//      run of 82 Hz). A median ignores a lone wild value entirely, where an
//      average would let it yank the result. This is the de-jitter that matters
//      most for a tuner: the displayed note shouldn't twitch between E2 and E3.
//
//   2. EMA (exponential moving average) — smooths the *remaining* small wobble
//      so the cents needle glides instead of vibrating. Same one-pole filter
//      idea as `AudioLevel.smooth`, applied to frequency.
//
//      raw estimates → [median window] → [EMA] → displayed frequency
//

import Foundation

/// Stateful smoother for a stream of frequency readings.
///
/// WHY A `struct` (value type) WITH `mutating` METHODS?
/// It holds a little history, but it has no *identity* — it's just data. A
/// `struct` gives us cheap, predictable, copy-on-assign semantics and keeps the
/// state explicit. The owning detector keeps one instance and calls `push` on it
/// each buffer. `mutating` marks the methods that change that stored state.
struct PitchSmoother {

    // MARK: Configuration

    /// How many recent raw readings the median looks at. Odd numbers have a
    /// single unambiguous middle element. 5 covers ~0.5 s at our buffer rate —
    /// long enough to reject a stray reading, short enough to still feel live.
    private let windowSize: Int

    /// EMA smoothing factor (0…1): near 0 = very smooth/slow, near 1 = snappy.
    /// 0.25 lets the needle settle quickly while still gliding.
    private let emaFactor: Float

    // MARK: State

    /// The most recent raw readings, oldest-first, capped at `windowSize`.
    private var window: [Float] = []

    /// The last smoothed output, or `nil` before the first reading (so the very
    /// first value isn't dragged up from zero).
    private var ema: Float?

    // MARK: Init

    init(windowSize: Int = 5, emaFactor: Float = 0.25) {
        // Force an odd window ≥ 1 so the median has a clean middle element.
        self.windowSize = max(1, windowSize | 1)
        self.emaFactor = min(max(emaFactor, 0), 1)
    }

    // MARK: Use

    /// Feed in one raw frequency estimate; get back the smoothed value to show.
    mutating func push(_ frequency: Float) -> Float {
        // Slide the window: append the newest, drop the oldest if we're full.
        window.append(frequency)
        if window.count > windowSize {
            window.removeFirst()
        }

        // MEDIAN: sort a copy and take the middle element. (Sorting a ≤5-element
        // array every buffer is negligible.) For an even-sized partial window
        // early on, integer `count / 2` picks the upper-middle — fine here.
        let median = window.sorted()[window.count / 2]

        // EMA: blend the median toward the previous smoothed value. On the first
        // reading there's nothing to blend with, so we seed straight from the
        // median (the `??` fallback).
        let previous = ema ?? median
        let smoothed = previous + emaFactor * (median - previous)
        ema = smoothed
        return smoothed
    }

    /// Forget all history — call when the signal drops out (silence/gate closes)
    /// so a new note starts clean instead of gliding from the old pitch.
    mutating func reset() {
        window.removeAll(keepingCapacity: true)
        ema = nil
    }
}
