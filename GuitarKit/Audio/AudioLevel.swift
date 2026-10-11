//
//  AudioLevel.swift
//  GuitarKit
//
//  The PURE math that turns a raw audio buffer into a 0...1 "loudness" number
//  we can drive a meter with. No AVFoundation, no UI, no hardware here — just
//  Double-in/Double-out functions. That separation is deliberate: this is the
//  part we can unit-test deterministically (feed known samples → assert known
//  level), while the noisy hardware bits live behind a protocol elsewhere.
//
//  THE PIPELINE (per audio buffer):
//      raw samples  →  RMS  →  dBFS  →  normalize to 0...1  →  smooth (EMA)
//
//  Each step is a small, separately-testable function below.
//

import Foundation

/// A namespace (empty `enum`, same trick as `GKColor`/`GKFont`) bundling the
/// pure level-metering math. Callers write `AudioLevel.rms(of:)` etc. Marked
/// `enum` with no cases so it can never be instantiated — it's just a home for
/// these `static` functions.
nonisolated enum AudioLevel {

    // MARK: - RMS (Root Mean Square)

    /// The **RMS** (root-mean-square) of a block of audio samples — the standard
    /// way to measure the "average loudness" of a signal.
    ///
    /// WHY NOT JUST AVERAGE THE SAMPLES?
    /// Audio samples swing positive and negative around zero (that *is* the
    /// sound wave). A plain average of a symmetric wave is ~0 no matter how loud
    /// it is. RMS fixes this by squaring every sample first (making everything
    /// positive and emphasizing big excursions), taking the *mean* of those
    /// squares, then the square *root* to get back to the original units. The
    /// result is a single non-negative number that grows with loudness.
    ///
    /// For typical PCM audio each sample is already in roughly `-1.0 ... 1.0`,
    /// so RMS comes out in `0.0 ... 1.0` as well (1.0 ≈ a full-scale tone).
    ///
    /// - Parameter samples: one buffer of mono audio samples.
    /// - Returns: the RMS amplitude (0 for silence / an empty buffer).
    static func rms(of samples: [Float]) -> Float {
        // An empty buffer has no energy. Guard first so we never divide by zero.
        guard !samples.isEmpty else { return 0 }

        // Sum of squares. `reduce` is a higher-order function: start at 0 and
        // fold each sample into the accumulator. We accumulate in `Float` to
        // match the sample type. (For very long buffers `Double` would be more
        // numerically precise, but audio buffers here are only a few thousand
        // samples, so `Float` is fine and faster.)
        let sumOfSquares = samples.reduce(Float(0)) { runningTotal, sample in
            runningTotal + sample * sample
        }

        // mean of the squares, then the square root → RMS.
        let meanSquare = sumOfSquares / Float(samples.count)
        return sqrt(meanSquare)
    }

    // MARK: - Normalization to a 0...1 meter value

    /// The quietest RMS we treat as "silence" → maps to a meter value of 0.
    /// Below this (the noise floor of a typical phone mic in a quiet room) we
    /// don't want the meter twitching. Expressed in **dBFS** (decibels relative
    /// to full scale, where 0 dBFS is the loudest possible and everything else
    /// is negative). -60 dBFS is very quiet.
    static let floorDB: Float = -60

    /// The RMS we treat as "as loud as the meter goes" → maps to a value of 1.
    /// -6 dBFS is a strong, healthy plucked-string signal without requiring an
    /// ear-splitting full-scale 0 dBFS to peg the meter.
    static let ceilingDB: Float = -6

    /// Convert a raw RMS amplitude to a friendly **0...1 meter value** on a
    /// perceptual (decibel) scale.
    ///
    /// WHY DECIBELS, NOT THE RAW RMS?
    /// Human hearing is logarithmic: the jump from a whisper to speech is a huge
    /// *ratio* but a tiny *absolute* RMS change. If we drove the meter with raw
    /// RMS, quiet-but-clearly-audible playing would barely move it and only a
    /// blast would fill it. Converting to decibels (a log scale) and then
    /// linearly mapping our [floor, ceiling] dB window onto [0, 1] gives a meter
    /// that responds the way your ear expects.
    ///
    /// STEPS:
    ///   1. `20 * log10(rms)` → amplitude in dBFS. (20·log10 is the standard
    ///      amplitude-ratio-to-decibels formula; energy/power uses 10·log10.)
    ///   2. Linearly remap [floorDB ... ceilingDB] → [0 ... 1].
    ///   3. Clamp so we never return below 0 or above 1.
    ///
    /// - Parameter rms: an RMS amplitude (typically 0...1) from `rms(of:)`.
    /// - Returns: a clamped meter value in `0...1`.
    static func meterValue(fromRMS rms: Float) -> Float {
        // Silence (or any non-positive value) is a clean 0 — and crucially
        // avoids `log10(0)` which is -infinity.
        guard rms > 0 else { return 0 }

        // 1) amplitude → decibels relative to full scale.
        let db = 20 * log10(rms)

        // 2) where does `db` fall within our [floor ... ceiling] window, as a
        // 0...1 fraction? (db − floor) / (ceiling − floor).
        let normalized = (db - floorDB) / (ceilingDB - floorDB)

        // 3) clamp into 0...1. `min`/`max` chained is the idiomatic clamp.
        return min(max(normalized, 0), 1)
    }

    // MARK: - Smoothing (exponential moving average)

    /// Smooth a fast-jittering signal with an **exponential moving average
    /// (EMA)**, a.k.a. a one-pole low-pass filter.
    ///
    /// WHY SMOOTH?
    /// Raw per-buffer levels jump around dozens of times a second; a meter wired
    /// directly to them looks like static. EMA blends each new reading with the
    /// previous *smoothed* value, so the meter glides instead of flickering.
    ///
    /// THE FORMULA:
    ///     newSmoothed = previous + factor * (target − previous)
    /// Equivalently `previous*(1−factor) + target*factor`. `factor` is the
    /// **smoothing factor** in `0...1`:
    ///   • near 0 → very smooth/slow (mostly keeps the old value)
    ///   • near 1 → barely smoothed (snaps to the new value)
    ///
    /// - Parameters:
    ///   - previous: the last smoothed value.
    ///   - target: the new raw reading to move toward.
    ///   - factor: how quickly to approach `target` (0...1). Defaults to 0.2,
    ///     a calm meter that still feels responsive.
    /// - Returns: the new smoothed value.
    static func smooth(previous: Float, target: Float, factor: Float = 0.2) -> Float {
        // Defensive clamp of the factor so a bad caller can't make the filter
        // overshoot or run backwards.
        let f = min(max(factor, 0), 1)
        return previous + f * (target - previous)
    }
}
