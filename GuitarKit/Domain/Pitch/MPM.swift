//
//  MPM.swift
//  GuitarKit
//
//  The PURE pitch-detection math: the McLeod Pitch Method (MPM).
//
//  Like `AudioLevel`, this file is deliberately hardware-free — `[Float]` in,
//  a frequency estimate out. No AVFoundation, no UI. That separation is what
//  lets us unit-test detection deterministically by feeding it a *synthetic*
//  sine wave (we know its exact frequency) and asserting the answer.
//
//  WHAT PROBLEM ARE WE SOLVING?
//  A plucked string produces a periodic wave. "What note is this?" really means
//  "what is the period of this wave?" — the fundamental frequency. Naive
//  approaches (count zero-crossings; take the biggest FFT bin) fall apart on
//  real instruments because a string's *overtones* (harmonics at 2×, 3×, ...
//  the fundamental) are often louder than the fundamental itself. That causes
//  "octave errors": reporting E3 when you played E2.
//
//  MPM is a time-domain method designed to resist exactly that. It is built on
//  the NSDF (Normalized Square Difference Function), explained below.
//
//  REFERENCE: Philip McLeod & Geoff Wyvill, "A Smarter Way to Find Pitch" (2005).
//

import Accelerate

/// A namespace (empty `enum`, same pattern as `AudioLevel`) holding the pure
/// MPM math. Callers write `MPM.detectPitch(...)`.
enum MPM {

    // MARK: - Result type

    /// One detection result: the estimated fundamental frequency plus a
    /// *clarity* score in 0...1 (how confidently periodic the signal is — 1.0
    /// is a pure sustained tone, low values are noise/transients).
    struct Estimate: Equatable {
        let frequency: Float
        let clarity: Float
    }

    // MARK: - Tuning constants

    /// The fraction of the strongest peak a candidate must reach to be accepted
    /// as the fundamental. MPM's key trick for beating octave errors: rather
    /// than taking the single tallest peak (which may be a harmonic), we take
    /// the *first* peak that is "tall enough" (≥ k · tallest). The true
    /// fundamental's peak comes first (at the longest period) and is usually
    /// nearly as tall as any harmonic's, so this reliably picks it. 0.9 is the
    /// value McLeod recommends.
    private static let peakThresholdRatio: Float = 0.9

    // MARK: - Public entry point

    /// Estimate the fundamental frequency of one buffer of mono samples.
    ///
    /// - Parameters:
    ///   - samples: one window of audio (e.g. 4096 samples). Longer windows are
    ///     needed to "see" a full period of low bass notes — at 44.1 kHz, a
    ///     41 Hz low-B repeats only ~10.7 times in 4096 samples, which is the
    ///     practical floor for this window size.
    ///   - sampleRate: samples per second (e.g. 44100), used to convert a period
    ///     measured in samples into a frequency in Hz.
    ///   - minFrequency / maxFrequency: the search range. Restricting it both
    ///     speeds things up and rejects out-of-range artifacts. Defaults span a
    ///     little below a bass low-B (~31 Hz) up past the highest guitar/violin
    ///     fundamentals.
    ///   - clarityThreshold: reject the estimate if even the best peak is below
    ///     this (i.e. the signal isn't convincingly periodic — noise or silence).
    /// - Returns: an `Estimate`, or `nil` if no confident pitch was found.
    static func detectPitch(
        samples: [Float],
        sampleRate: Double,
        minFrequency: Float = 30,
        maxFrequency: Float = 1500,
        clarityThreshold: Float = 0.8
    ) -> Estimate? {
        let n = samples.count
        // Need at least a couple of samples and a sane sample rate.
        guard n > 2, sampleRate > 0 else { return nil }

        // Convert the frequency search range into a *lag* (period-in-samples)
        // range. period = sampleRate / frequency, so a HIGH frequency is a
        // SHORT lag and a LOW frequency is a LONG lag.
        //   minLag ← maxFrequency (shortest period we'll consider)
        //   maxLag ← minFrequency (longest period we'll consider)
        let minLag = max(2, Int(sampleRate / Double(maxFrequency)))
        // We can't measure a period longer than the buffer itself; cap maxLag.
        let maxLag = min(n - 1, Int(sampleRate / Double(minFrequency)))
        guard maxLag > minLag else { return nil }

        // 1) Build the NSDF over lags 0...maxLag.
        let nsdf = normalizedSquareDifference(samples, maxLag: maxLag)
        guard !nsdf.isEmpty else { return nil }

        // 2) Find the candidate peaks (the "key maxima").
        let peaks = keyMaxima(in: nsdf, minLag: minLag)
        guard !peaks.isEmpty else { return nil }

        // 3) Choose the fundamental: first peak ≥ 0.9 · tallest peak.
        let tallest = peaks.map(\.value).max() ?? 0
        // Overall confidence gate: if even the tallest peak is weak, it's noise.
        guard tallest >= clarityThreshold else { return nil }

        let cutoff = tallest * peakThresholdRatio
        // `first(where:)` walks peaks in increasing-lag order, so we naturally
        // get the longest-period (lowest-frequency = fundamental) candidate.
        let chosen = peaks.first { $0.value >= cutoff } ?? peaks[0]

        // 4) Lag → frequency. The chosen lag is fractional (parabolic-refined),
        // so this resolves to a precise, between-samples frequency.
        let frequency = Float(sampleRate) / chosen.lag
        guard frequency >= minFrequency, frequency <= maxFrequency else { return nil }

        // Clamp clarity into 0...1 (interpolation can nudge it slightly over 1).
        return Estimate(frequency: frequency, clarity: min(max(chosen.value, 0), 1))
    }

    // MARK: - Step 1: the NSDF

    /// Compute the **Normalized Square Difference Function** for lags 0...maxLag.
    ///
    /// WHAT IT IS, INTUITIVELY:
    /// For each candidate lag τ (a guess at the period, in samples), we ask
    /// "if I shift the signal by τ and overlay it on itself, how well does it
    /// line up?" A periodic signal lines up almost perfectly when τ equals its
    /// true period (and multiples of it) → NSDF near +1 there, and poorly
    /// elsewhere. So peaks in the NSDF mark candidate periods.
    ///
    /// THE FORMULA (McLeod's type-II, windowed):
    ///       NSDF(τ) = 2·r(τ) / m(τ)
    ///   where, summing j over the overlapping region 0 … (N−1−τ):
    ///       r(τ) = Σ  x[j]·x[j+τ]                  (autocorrelation)
    ///       m(τ) = Σ ( x[j]² + x[j+τ]² )           (energy normalizer)
    ///   The 2·r/m form keeps the result in −1…+1 regardless of loudness, so the
    ///   same clarity thresholds work for soft and loud playing alike.
    ///
    /// HOW WE COMPUTE IT EFFICIENTLY:
    ///   • r(τ): a dot product of the signal with a shifted copy of itself. We
    ///     use Accelerate's `vDSP_dotpr`, which is vectorized (SIMD) — far faster
    ///     than a hand-written Swift loop.
    ///   • m(τ): rather than re-summing squares for every τ (O(N) each), we use a
    ///     *prefix-sum* of squares so each m(τ) is O(1). See the derivation below.
    static func normalizedSquareDifference(_ samples: [Float], maxLag: Int) -> [Float] {
        let n = samples.count
        guard n > 1, maxLag >= 1, maxLag < n else { return [] }

        // prefix[k] = sum of squares of the first k samples (prefix[0] = 0).
        // This lets us read "sum of squares of any sub-range" in O(1):
        //     Σ_{i=a}^{b-1} x[i]²  =  prefix[b] − prefix[a]
        var prefix = [Float](repeating: 0, count: n + 1)
        for i in 0..<n {
            prefix[i + 1] = prefix[i] + samples[i] * samples[i]
        }
        let totalEnergy = prefix[n]
        // All-zero (silent) buffer → no periodicity to find.
        guard totalEnergy > 0 else { return [] }

        var nsdf = [Float](repeating: 0, count: maxLag + 1)

        // Borrow a raw pointer to the samples so `vDSP_dotpr` can read the
        // shifted slice (`base + tau`) without copying.
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }

            for tau in 0...maxLag {
                let overlap = n - tau            // number of overlapping samples

                // r(τ): dot product of x[0..<overlap] with x[τ..<τ+overlap].
                var r: Float = 0
                vDSP_dotpr(base, 1, base + tau, 1, &r, vDSP_Length(overlap))

                // m(τ) via prefix sums. Derivation:
                //   Σ_{j=0}^{overlap-1} x[j]²       = prefix[overlap]
                //   Σ_{j=0}^{overlap-1} x[j+τ]²     = prefix[n] − prefix[τ]
                //   m(τ) = those two added together.
                let m = prefix[overlap] + (totalEnergy - prefix[tau])

                nsdf[tau] = m > 0 ? (2 * r / m) : 0
            }
        }

        return nsdf
    }

    // MARK: - Step 2: pick the key maxima

    /// A candidate period: the (parabola-refined) `lag` in samples and the NSDF
    /// `value` there (its "height", ~periodicity strength).
    private struct Peak {
        let lag: Float
        let value: Float
    }

    /// Find the **key maxima** of the NSDF: the single highest point inside each
    /// "positive hump" of the curve.
    ///
    /// WHY HUMPS, NOT EVERY LITTLE BUMP?
    /// The NSDF starts at +1 (lag 0 always lines up perfectly with itself), dips
    /// negative, then rises into a hump around the true period, dips, rises into
    /// the next hump at 2× the period, and so on. We want ONE representative per
    /// hump — the tallest point between an upward zero-crossing and the next
    /// downward one — because those are the real period candidates.
    private static func keyMaxima(in nsdf: [Float], minLag: Int) -> [Peak] {
        let maxLag = nsdf.count - 1
        guard maxLag >= 2 else { return [] }

        var peaks: [Peak] = []

        // STEP A: skip the initial positive lobe at lag 0. It always lines up
        // (NSDF ≈ 1) and tells us nothing about the period, so we advance past
        // it until the curve first goes non-positive.
        var i = 1
        while i < maxLag, nsdf[i] > 0 { i += 1 }
        // STEP B: skip the following negative region to the first *upward* zero
        // crossing — the start of the first real hump.
        while i < maxLag, nsdf[i] <= 0 { i += 1 }

        // STEP C: walk to the END of the buffer (inclusive of the final lag),
        // tracking the tallest sample inside the current positive hump. Each hump
        // is bounded by zero crossings, so its single highest SAMPLE *is* its peak
        // — no separate "local maximum" test is needed, and using the running
        // argmax means a peak sitting on the very last lag is captured too.
        //
        // WHY THIS MATTERS (the boundary bug): the old loop ran `while i < maxLag`
        // and only recorded interior local maxima (`nsdf[i] > nsdf[i-1] && …`). For
        // the lowest notes — whose period approaches the buffer length — the true
        // hump can crest at or right against `maxLag`, where the local-max test
        // never fires and the loop never visits it, so that final hump (the actual
        // fundamental) was silently dropped. Tracking the argmax across all lags up
        // to and including `maxLag` fixes that without changing normal-note results
        // (an interior hump's argmax equals its local max).
        //
        // `currentMaxIndex == 0` is the "not currently inside a hump" sentinel; the
        // first hump starts at i >= 1 (lag 0's lobe was skipped above), so index 0
        // is never a real candidate.
        var currentMaxIndex = 0
        while i <= maxLag {
            if nsdf[i] > 0 {
                // Inside a hump: keep the tallest sample seen so far.
                if currentMaxIndex == 0 || nsdf[i] > nsdf[currentMaxIndex] {
                    currentMaxIndex = i
                }
            } else if currentMaxIndex != 0 {
                // Curve went non-positive → the hump just closed. Record its peak
                // (parabola-refined), but only at/beyond minLag (ignore peaks that
                // imply too-high a pitch), then reset to await the next hump.
                if currentMaxIndex >= minLag {
                    peaks.append(parabolicPeak(nsdf, around: currentMaxIndex))
                }
                currentMaxIndex = 0
            }
            i += 1
        }
        // Flush a hump still open at the buffer's end (the case the old code missed
        // when the crest landed on the final lag).
        if currentMaxIndex >= minLag {
            peaks.append(parabolicPeak(nsdf, around: currentMaxIndex))
        }

        return peaks
    }

    // MARK: - Step 2b: sub-sample peak refinement

    /// Refine a peak's position to *between* samples by fitting a parabola
    /// through the three points (x−1, x, x+1).
    ///
    /// WHY: the true period rarely lands exactly on an integer sample lag. The
    /// discrete peak at index `x` is the nearest sample, but the real summit of
    /// the smooth NSDF curve sits a fraction to one side. Fitting a parabola to
    /// the peak and its two neighbours and taking that parabola's vertex gives a
    /// fractional lag — turning a coarse "nearest sample" period into a precise
    /// one. For a tuner this is the difference between ±~3 cents and ±~30 cents.
    private static func parabolicPeak(_ a: [Float], around x: Int) -> Peak {
        // Need both neighbours; at the very edges just return the raw sample.
        guard x > 0, x < a.count - 1 else { return Peak(lag: Float(x), value: a[x]) }

        let y0 = a[x - 1]   // left neighbour
        let y1 = a[x]       // the peak sample
        let y2 = a[x + 1]   // right neighbour

        // Vertex of the parabola through (−1,y0),(0,y1),(1,y2), offset from x.
        let denom = y0 - 2 * y1 + y2
        // denom == 0 → the three points are colinear (no curvature); fall back.
        guard denom != 0 else { return Peak(lag: Float(x), value: y1) }

        let delta = 0.5 * (y0 - y2) / denom          // horizontal shift, in samples
        let refinedLag = Float(x) + delta
        // Height of the parabola at its vertex (a slightly better clarity value).
        let refinedValue = y1 - 0.25 * (y0 - y2) * delta
        return Peak(lag: refinedLag, value: refinedValue)
    }
}
