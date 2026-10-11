//
//  YIN.swift
//  GuitarKit
//
//  The PURE YIN pitch-detection algorithm — the other detector behind the
//  swappable/ensemble layer (`PitchAlgorithm`). Like `MPM`, it's hardware-free
//  (`[Float]` in, an estimate out) so it's unit-testable against synthetic tones.
//
//  REFERENCE: Alain de Cheveigné & Hideki Kawahara, "YIN, a fundamental
//  frequency estimator for speech and music" (2002).
//
//  THE IDEA (a cousin of autocorrelation, tuned to avoid octave errors):
//  For each candidate period τ (a lag in samples) we measure how DIFFERENT the
//  signal is from a copy of itself shifted by τ:
//
//      d(τ) = Σ_j ( x[j] − x[j+τ] )²          ("difference function")
//
//  At the true period d(τ) dips toward 0 (the signal lines up with its shifted
//  self). The trouble: d also dips at τ = 0 and tends to dip MORE at longer lags,
//  which invites octave errors. YIN's key fix is the CUMULATIVE MEAN NORMALIZED
//  difference:
//
//      d'(τ) = d(τ) / [ (1/τ) · Σ_{k=1..τ} d(k) ]      (and d'(0) = 1)
//
//  Dividing by the running average flattens that bias, so the FIRST dip below a
//  small absolute threshold is the fundamental — not a sub-octave. We then refine
//  that lag with a parabola for sub-sample (sub-cent) precision.
//
//  EFFICIENCY: we compute d(τ) the same fast way `MPM` builds its NSDF — note
//  d(τ) = e₀(τ) + e_τ(τ) − 2·r(τ), where r(τ) is the autocorrelation (one
//  vectorized `vDSP_dotpr`) and the two energy terms come from a prefix-sum of
//  squares (O(1) each). So YIN costs about the same as MPM.
//

import Accelerate

/// A namespace (empty `enum`, like `MPM`/`AudioLevel`) holding the pure YIN math.
nonisolated enum YIN {

    /// The absolute threshold d'(τ) must dip below to be accepted as the period.
    /// 0.10–0.15 is the paper's recommended range; 0.15 is a touch more forgiving,
    /// which suits a decaying guitar note.
    private static let threshold: Float = 0.15

    /// Estimate the fundamental of one buffer. Returns the best raw estimate
    /// (frequency + clarity); the caller applies the clarity/level gates.
    ///
    /// `clarity` is `1 − d'(τ)` at the chosen lag: ~1 when the shifted signal
    /// matches almost perfectly (very periodic), lower for noisy/decaying input —
    /// the same 0…1 scale MPM's clarity uses, so the gates work for both.
    static func detectPitch(
        samples: [Float],
        sampleRate: Double,
        minFrequency: Float = 30,
        maxFrequency: Float = 1500
    ) -> PitchEstimate? {
        let n = samples.count
        guard n > 2, sampleRate > 0 else { return nil }

        // Frequency range → lag range. High freq = short lag, low freq = long lag.
        let minLag = max(2, Int(sampleRate / Double(maxFrequency)))
        let maxLag = min(n - 1, Int(sampleRate / Double(minFrequency)))
        guard maxLag > minLag else { return nil }

        // 1) Difference function d(τ), built from autocorrelation + energies.
        // prefix[k] = Σ of the first k squared samples (prefix[0] = 0), so the
        // sum of squares of any sub-range is a single subtraction.
        var prefix = [Float](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + samples[i] * samples[i] }
        let totalEnergy = prefix[n]
        guard totalEnergy > 0 else { return nil }     // silence → nothing to find

        var d = [Float](repeating: 0, count: maxLag + 1)   // d[0] = 0
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for tau in 1...maxLag {
                let overlap = n - tau
                // r(τ): autocorrelation = dot product of x with x shifted by τ.
                var r: Float = 0
                vDSP_dotpr(base, 1, base + tau, 1, &r, vDSP_Length(overlap))
                // Energies of the two overlapping halves, via prefix sums.
                let e0   = prefix[overlap]                 // Σ x[j]²   for j < overlap
                let eTau = totalEnergy - prefix[tau]        // Σ x[j+τ]² for j < overlap
                d[tau] = e0 + eTau - 2 * r
            }
        }

        // 2) Cumulative mean normalized difference d'(τ).
        var dPrime = [Float](repeating: 1, count: maxLag + 1)   // d'(0) = 1
        var runningSum: Float = 0
        for tau in 1...maxLag {
            runningSum += d[tau]
            dPrime[tau] = runningSum > 0 ? d[tau] * Float(tau) / runningSum : 1
        }

        // 3) Absolute threshold: the FIRST lag (≥ minLag) where d' dips below the
        // threshold, walked down to the bottom of that dip. This "first deep dip"
        // rule is what picks the fundamental rather than a louder harmonic.
        var tauEstimate = -1
        var tau = minLag
        while tau <= maxLag {
            if dPrime[tau] < threshold {
                while tau + 1 <= maxLag, dPrime[tau + 1] < dPrime[tau] { tau += 1 }
                tauEstimate = tau
                break
            }
            tau += 1
        }
        // Nothing crossed the threshold → fall back to the global minimum of d'
        // in range (the most periodic lag we could find).
        if tauEstimate == -1 {
            var bestTau = minLag
            var bestVal = dPrime[minLag]
            for t in (minLag + 1)...maxLag where dPrime[t] < bestVal {
                bestVal = dPrime[t]; bestTau = t
            }
            tauEstimate = bestTau
        }

        // 4) Parabolic refinement of the dip's location (sub-sample lag), then
        // convert lag → frequency.
        let refined = parabolicMinimum(dPrime, around: tauEstimate)
        let frequency = Float(sampleRate) / refined.lag
        guard frequency >= minFrequency, frequency <= maxFrequency else { return nil }

        let clarity = min(max(1 - refined.value, 0), 1)
        return PitchEstimate(frequency: frequency, clarity: clarity)
    }

    /// Fit a parabola through (x−1, x, x+1) and return its VERTEX (a minimum here),
    /// giving a fractional lag + the interpolated d' value there. Same refinement
    /// idea as MPM's peak interpolation, but for a dip rather than a peak.
    private static func parabolicMinimum(_ a: [Float], around x: Int) -> (lag: Float, value: Float) {
        guard x > 0, x < a.count - 1 else { return (Float(x), a[x]) }
        let y0 = a[x - 1], y1 = a[x], y2 = a[x + 1]
        let denom = y0 - 2 * y1 + y2
        guard denom != 0 else { return (Float(x), y1) }      // colinear → no curvature
        let delta = 0.5 * (y0 - y2) / denom
        let lag = Float(x) + delta
        let value = y1 - 0.25 * (y0 - y2) * delta
        return (lag, value)
    }
}
