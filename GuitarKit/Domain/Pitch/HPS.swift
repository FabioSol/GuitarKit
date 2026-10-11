//
//  HPS.swift
//  GuitarKit
//
//  The PURE Harmonic Product Spectrum pitch detector — a FREQUENCY-domain detector
//  to complement the time-domain `MPM`/`YIN`. Hardware-free (`[Float]` in, an
//  estimate out), so it's unit-testable against synthetic tones like the others.
//
//  THE IDEA:
//  A pitched note at fundamental f has energy at its harmonics f, 2f, 3f, 4f… So if
//  we take the magnitude spectrum and MULTIPLY it by copies of itself compressed by
//  ×2, ×3, ×4… (sliding the 2nd harmonic's peak back onto f, the 3rd onto f, etc.):
//
//      HPS(f) = |X(f)| · |X(2f)| · |X(3f)| · … · |X(R·f)|
//
//  every term is large ONLY at the true fundamental — the one frequency where all
//  the harmonics line up — so the product spikes there and collapses everywhere
//  else (a lone loud harmonic gets multiplied by near-zero neighbours). We pick the
//  peak, then refine it with a parabola on the magnitude spectrum for sub-bin
//  accuracy.
//
//  WHY ADD IT (the low-string motivation):
//  The flaky low strings are a WEAK-FUNDAMENTAL problem — the 2nd/3rd harmonics are
//  louder than f itself, which can lure an autocorrelation detector up an octave.
//  HPS is the opposite: it REQUIRES agreement across the harmonics, so a weak-but-
//  present fundamental still wins. Its own weakness (coarse low-frequency bin
//  resolution, and a tendency to favour an octave when the true f0 bin is genuinely
//  empty) is exactly why it rides in the ENSEMBLE as a tie-breaker rather than
//  replacing the others.
//
//  REFERENCE: Noll, "Pitch determination of human speech…" (1969) — the original
//  cepstrum/HPS lineage.
//

import Accelerate

/// A namespace (empty `enum`, like `MPM`/`YIN`) holding the pure HPS math.
nonisolated enum HPS {

    /// How many harmonics to fold together (the product runs |X(f)|·…·|X(R·f)|).
    /// Five is the classic choice: enough to lock onto the fundamental, few enough
    /// that we don't run off the top of the spectrum for high notes.
    fileprivate static let harmonics = 5

    /// The FFT length we analyse at. We ZERO-PAD up to this so the magnitude
    /// spectrum is finely sampled — crucial for the low strings, where one raw bin
    /// can span many cents. Padding doesn't invent resolution (it can't separate two
    /// close partials), but it interpolates the spectrum so the single dominant
    /// fundamental's peak is located accurately. 32768 @ 44.1 kHz ≈ 1.35 Hz/bin,
    /// and parabolic refinement takes it well below a cent's worth at guitar pitches.
    fileprivate static let fftSize = 32_768

    /// The FFT twiddle-factor table, built ONCE and reused across calls. Creating it
    /// per call (it precomputes thousands of trig factors) would be far too costly on
    /// the detection path. `nonisolated(unsafe)` because `FFTSetup` is an opaque
    /// pointer (not `Sendable`); we only ever read it, never mutate it, so sharing it
    /// is safe.
    nonisolated(unsafe) private static let fftSetup: FFTSetup? =
        vDSP_create_fftsetup(vDSP_Length(log2(Double(fftSize))), FFTRadix(kFFTRadix2))

    /// Estimate the fundamental of one buffer. Returns the best raw estimate
    /// (frequency + clarity); the caller applies the clarity/level gates. Mirrors
    /// `YIN.detectPitch`'s signature so `PitchAlgorithm` can swap them freely.
    ///
    /// `clarity` is the share of spectral energy that the detected harmonic series
    /// explains (0…1): ~1 for a clean tone whose energy sits on f and its
    /// harmonics, low for broadband noise whose energy is spread everywhere — the
    /// same scale MPM/YIN use, so the gates work for HPS too.
    static func detectPitch(
        samples: [Float],
        sampleRate: Double,
        minFrequency: Float = 30,
        maxFrequency: Float = 1500
    ) -> PitchEstimate? {
        guard sampleRate > 0,
              let (magnitudes, analysisCount) = magnitudeSpectrum(samples) else { return nil }
        let halfN = fftSize / 2

        // 1) HPS PRODUCT over the candidate fundamental bins. The top candidate bin
        // is bounded so its R-th harmonic still lands inside the spectrum.
        let hzPerBin = Double(sampleRate) / Double(fftSize)
        let minBin = max(1, Int(Double(minFrequency) / hzPerBin))
        let maxBin = min(
            Int(Double(maxFrequency) / hzPerBin),
            (halfN - 1) / harmonics
        )
        guard maxBin > minBin else { return nil }

        var bestBin = minBin
        var bestValue: Float = 0
        for i in minBin...maxBin {
            var product = magnitudes[i]
            var h = 2
            while h <= harmonics {
                product *= magnitudes[i * h]
                h += 1
            }
            if product > bestValue {
                bestValue = product
                bestBin = i
            }
        }
        guard bestValue > 0 else { return nil }

        // 2) REFINE. Parabolic interpolation on the LOG-magnitude spectrum around the
        // winning bin gives a fractional bin (sub-Hz), which we turn into a frequency.
        let fractionalBin = parabolicPeak(magnitudes, around: bestBin)
        let frequency = Float(fractionalBin * hzPerBin)
        guard frequency >= minFrequency, frequency <= maxFrequency else { return nil }

        // 3) CLARITY = harmonic energy ratio. How much of the band's energy sits on
        // the detected fundamental + its harmonics. Each partial is summed over a
        // window as wide as the zero-pad factor, because padding spreads every
        // partial's true main lobe across that many bins — sampling just one would
        // undercount the tone's real energy. High for a tonal note, low for noise.
        let padFactor = fftSize / analysisCount
        let clarity = harmonicEnergyRatio(
            magnitudes, fundamentalBin: fractionalBin,
            windowRadius: max(2, padFactor),
            minBin: minBin, maxBin: halfN - 1
        )
        return PitchEstimate(frequency: frequency, clarity: clarity)
    }

    // MARK: - Harmonic evidence for a GIVEN pitch

    /// How much of the in-band spectral energy sits on the harmonic series of
    /// `frequency` (0…1) — "does this sound look like ONE harmonic source at
    /// this pitch?" Unlike `detectPitch`, this doesn't search for a pitch, it
    /// checks one found elsewhere (by MPM/YIN), so it has none of HPS's
    /// pure-sine trouble: a sine's energy all sits on harmonic 1 → ~1.
    ///
    /// What scores LOW: a gliding voice (its upper harmonics smear across the
    /// window and leave their bins), a chord (the other notes' energy isn't on
    /// this series), clicks and noise (energy everywhere).
    ///
    /// - Parameters:
    ///   - harmonics: how many partials count as "the series". Guitar strings
    ///     are rich, so more than `detectPitch`'s five.
    ///   - minFrequency: the band's floor — energy below it isn't counted.
    static func harmonicity(of frequency: Float, in samples: [Float], sampleRate: Double,
                            harmonics: Int = 8, minFrequency: Float = 30) -> Float? {
        spectrum(of: samples, sampleRate: sampleRate)?
            .harmonicity(of: frequency, harmonics: harmonics, minFrequency: minFrequency)
    }

    // MARK: - A reusable spectrum (one FFT, several questions)

    /// One frame's magnitude spectrum, kept so several questions can be asked
    /// of it without re-running the FFT — the probabilistic tracker asks one
    /// per tracked string, every frame.
    struct Spectrum {
        fileprivate let magnitudes: [Float]
        fileprivate let analysisCount: Int
        let sampleRate: Double

        private var hzPerBin: Double { sampleRate / Double(HPS.fftSize) }
        /// Zero-padding spreads each partial over about this many bins.
        private var lobeRadius: Int { max(2, HPS.fftSize / analysisCount) }

        /// Share of in-band energy on `frequency`'s harmonic series (see
        /// `HPS.harmonicity`). A GLOBAL measure: any other sound anywhere in
        /// the band lowers it.
        func harmonicity(of frequency: Float, harmonics: Int = 8, minFrequency: Float = 30) -> Float? {
            guard frequency > 0, harmonics >= 1 else { return nil }
            return HPS.harmonicEnergyRatio(
                magnitudes, fundamentalBin: Double(frequency) / hzPerBin,
                harmonics: harmonics, windowRadius: lobeRadius,
                minBin: max(1, Int(Double(minFrequency) / hzPerBin)),
                maxBin: magnitudes.count - 1)
        }

        /// Do `frequency`'s partials STAND OUT LOCALLY? For each harmonic,
        /// the energy right on the partial over the energy in a neighbourhood
        /// four times wider, pooled across harmonics (0…1). A LOCAL measure:
        /// a voice or chord elsewhere in the spectrum doesn't lower it, so it
        /// answers "is this string still ringing underneath the
        /// interference?". Noise scores ~0.25 (the window/neighbourhood width
        /// ratio); a clean partial approaches 1.
        func salience(of frequency: Float, harmonics: Int = 6) -> Float? {
            guard frequency > 0, harmonics >= 1 else { return nil }
            let r = lobeRadius
            var on: Float = 0, around: Float = 0
            for k in 1...harmonics {
                let center = Int((Double(frequency) * Double(k) / hzPerBin).rounded())
                guard center - 4 * r >= 1, center + 4 * r < magnitudes.count else { break }
                for b in (center - 4 * r)...(center + 4 * r) {
                    let e = magnitudes[b] * magnitudes[b]
                    around += e
                    if abs(b - center) <= r { on += e }
                }
            }
            return around > 0 ? on / around : nil
        }

        /// Re-measure a pitch from the spectrum near a guess: find the
        /// strongest of the first few partials within ±`searchCents` of where
        /// the guess puts them, interpolate its peak, and divide by its
        /// harmonic number. Prefers the fundamental unless it's much weaker
        /// (low strings), since higher partials of a stiff string run a
        /// little sharp.
        func refinedPitch(near guess: Float, searchCents: Float = 40) -> Float? {
            guard guess > 0 else { return nil }
            var best: (k: Int, bin: Double, energy: Float)?
            var fundamentalEnergy: Float = 0
            for k in 1...3 {
                let center = Double(guess) * Double(k) / hzPerBin
                let span = max(1, Int((center * (pow(2, Double(searchCents) / 1200) - 1)).rounded(.up)))
                let lo = max(1, Int(center) - span), hi = min(magnitudes.count - 2, Int(center) + span)
                guard hi > lo else { continue }
                var peak = lo
                for b in lo...hi where magnitudes[b] > magnitudes[peak] { peak = b }
                let energy = magnitudes[peak] * magnitudes[peak]
                if k == 1 { fundamentalEnergy = energy }
                // A higher partial wins only if the fundamental is under a quarter of it.
                if best == nil || (energy > best!.energy && (k == 1 || fundamentalEnergy < energy / 4)) {
                    best = (k, HPS.parabolicPeak(magnitudes, around: peak), energy)
                }
            }
            guard let best, best.energy > 0 else { return nil }
            return Float(best.bin * hzPerBin / Double(best.k))
        }
    }

    /// The spectrum of one buffer, or `nil` for silence / too little signal.
    static func spectrum(of samples: [Float], sampleRate: Double) -> Spectrum? {
        guard sampleRate > 0, let (magnitudes, count) = magnitudeSpectrum(samples) else { return nil }
        return Spectrum(magnitudes: magnitudes, analysisCount: count, sampleRate: sampleRate)
    }

    // MARK: - Helpers

    /// Hann-window + zero-pad one buffer and return its magnitude spectrum
    /// (`fftSize / 2` bins) and how many real samples went in. `nil` for
    /// silence or too little signal to resolve low pitches.
    private static func magnitudeSpectrum(_ samples: [Float]) -> ([Float], Int)? {
        // Need a reasonable chunk of signal to resolve low pitches at all.
        let analysisCount = min(samples.count, fftSize)
        guard analysisCount >= 1_024, let setup = fftSetup else { return nil }

        // WINDOW + ZERO-PAD. A Hann window tames spectral leakage (so each
        // partial is a clean lobe the parabola can sit on); the rest of the
        // fftSize-long buffer stays zero (the zero-padding that sharpens the
        // frequency estimate). Done with vDSP (Accelerate's vector maths) —
        // it's as fast in a Debug build as in Release, where a plain Swift
        // loop over thousands of samples is not.
        var windowed = [Float](repeating: 0, count: fftSize)
        let window = hannWindow(count: analysisCount)
        samples.withUnsafeBufferPointer { src in
            windowed.withUnsafeMutableBufferPointer { dst in
                vDSP_vmul(src.baseAddress!, 1, window, 1, dst.baseAddress!, 1, vDSP_Length(analysisCount))
            }
        }
        var energy: Float = 0
        vDSP_svesq(windowed, 1, &energy, vDSP_Length(analysisCount))
        guard energy > 0 else { return nil }   // silence → nothing to find

        // REAL FFT → magnitude spectrum. We use vDSP's packed real FFT: the
        // real input is reinterpreted as `n/2` complex pairs, transformed in
        // place, then `zvabs` gives the magnitude of each of the n/2 bins.
        let halfN = fftSize / 2
        let log2n = vDSP_Length(log2(Double(fftSize)))
        var real = [Float](repeating: 0, count: halfN)
        var imag = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!,
                                            imagp: imagPtr.baseAddress!)
                // Pack the real samples (even→real, odd→imag) for the real FFT.
                windowed.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cplx in
                        vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(halfN))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // |X(k)| for each bin. (Bin 0 mixes DC + Nyquist in zrip's packing,
                // but we never use it — minFrequency keeps the search well above it.)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }
        return (magnitudes, analysisCount)
    }

    /// Fit a parabola through the log-magnitudes at (x−1, x, x+1) and return its
    /// vertex as a fractional bin. Log domain because a Hann main lobe is very
    /// nearly a parabola there, which is what makes the interpolation accurate.
    fileprivate static func parabolicPeak(_ mag: [Float], around x: Int) -> Double {
        guard x > 0, x < mag.count - 1 else { return Double(x) }
        let eps: Float = 1e-12
        let a = log(mag[x - 1] + eps)
        let b = log(mag[x]     + eps)
        let c = log(mag[x + 1] + eps)
        let denom = a - 2 * b + c
        guard denom != 0 else { return Double(x) }
        let delta = 0.5 * (a - c) / denom               // in (−0.5, 0.5)
        return Double(x) + Double(delta)
    }

    /// The fraction of in-band spectral ENERGY explained by the harmonic series of
    /// `fundamentalBin`. Sums |X|² in a ±`windowRadius`-bin window around each of the
    /// first `harmonics` partials, over the total in-band energy. 0…1.
    fileprivate static func harmonicEnergyRatio(
        _ mag: [Float], fundamentalBin: Double, harmonics: Int = HPS.harmonics,
        windowRadius: Int, minBin: Int, maxBin: Int
    ) -> Float {
        guard maxBin >= minBin else { return 0 }
        return mag.withUnsafeBufferPointer { m in
            /// Σ|X|² over bins lo...hi (vDSP: sum of squares).
            func energy(_ lo: Int, _ hi: Int) -> Float {
                guard hi >= lo else { return 0 }
                var e: Float = 0
                vDSP_svesq(m.baseAddress! + lo, 1, &e, vDSP_Length(hi - lo + 1))
                return e
            }
            // Total energy across the search band (denominator).
            let total = energy(minBin, maxBin)
            guard total > 0 else { return 0 }

            // Energy captured by the fundamental + harmonics (numerator). The
            // partials' windows come in increasing order, so remembering the
            // last bin counted is enough to never double-count where the
            // windows of a very low note's close harmonics overlap.
            var harmonic: Float = 0
            var lastCounted = minBin - 1
            for h in 1...max(harmonics, 1) {
                let center = Int((fundamentalBin * Double(h)).rounded())
                let lo = max(center - windowRadius, lastCounted + 1, minBin)
                let hi = min(center + windowRadius, maxBin)
                guard hi >= lo else { continue }
                harmonic += energy(lo, hi)
                lastCounted = hi
            }
            return min(max(harmonic / total, 0), 1)
        }
    }

    // MARK: - Hann window cache

    /// Hann windows by length. Every mic window has the same length, so this
    /// is computed once and reused; a lock keeps it safe to call from the
    /// background thread pitch detection runs on.
    private static let windowLock = NSLock()
    nonisolated(unsafe) private static var windows: [Int: [Float]] = [:]

    private static func hannWindow(count: Int) -> [Float] {
        windowLock.lock(); defer { windowLock.unlock() }
        if let cached = windows[count] { return cached }
        // Symmetric Hann: w[i] = 0.5 − 0.5·cos(2πi / (n−1)).
        let denom = Float(max(count - 1, 1))
        let w = (0..<count).map { 0.5 - 0.5 * cos(2 * .pi * Float($0) / denom) }
        windows[count] = w
        return w
    }
}
