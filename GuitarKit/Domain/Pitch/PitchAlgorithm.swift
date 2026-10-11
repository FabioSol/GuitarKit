//
//  PitchAlgorithm.swift
//  GuitarKit
//
//  ONE PITCH, SEVERAL WAYS TO FIND IT.
//
//  We ship more than one pitch-detection algorithm and let them be swapped (and
//  A/B-compared in the Tuner Lab). They all answer the same question — "what's
//  the fundamental frequency of this buffer?" — but they fail in different ways,
//  so being able to switch (or run an ENSEMBLE that cross-checks them) makes
//  detection more robust on tricky inputs like a plucked guitar low E.
//
//  The algorithms themselves stay PURE and hardware-free (`MPM`, `YIN`): `[Float]`
//  in, an estimate out. This file is the thin layer that picks between them and,
//  for `.ensemble`, combines their answers.
//

import Foundation

// MARK: - Shared result

/// One detection result shared by every algorithm: the estimated fundamental
/// frequency (Hz) and a 0…1 CLARITY score (how confidently periodic the signal
/// is — ~1 for a clean sustained tone, low for noise/transients). The detector
/// applies the clarity/level GATES; the algorithms just report what they found.
nonisolated public struct PitchEstimate: Equatable, Sendable {
    public let frequency: Float
    public let clarity: Float
    public init(frequency: Float, clarity: Float) {
        self.frequency = frequency
        self.clarity = clarity
    }
}

// MARK: - The swappable algorithm

/// Which detector to run. `CaseIterable`/`String`-raw so the Tuner Lab can list
/// them and persist a choice.
nonisolated public enum PitchAlgorithm: String, CaseIterable, Sendable {
    /// McLeod Pitch Method — the NSDF-based detector (good octave resistance).
    case mpm
    /// YIN — the cumulative-mean-normalized-difference detector (often steadier
    /// on guitar low strings).
    case yin
    /// HPS — the Harmonic Product Spectrum (frequency domain). Excels at
    /// weak-fundamental notes (it needs a real harmonic series; a pure sine fools
    /// it into a subharmonic, so it's primarily a tie-breaker — see `ensemble`).
    case hps
    /// Run them and cross-check — most robust. MPM + YIN agree most of the time;
    /// HPS is consulted only to break their octave disagreements.
    case ensemble

    /// A short label for the picker.
    public var label: String {
        switch self {
        case .mpm:      return "MPM"
        case .yin:      return "YIN"
        case .hps:      return "HPS"
        case .ensemble: return "Ensemble"
        }
    }

    /// Run this algorithm on one window and return its best RAW estimate (no
    /// clarity gate — the caller decides whether it's confident enough). The
    /// frequency search range spans a little below a 5-string bass low B up past
    /// the highest fundamentals we tune.
    public func detect(
        samples: [Float],
        sampleRate: Double,
        minFrequency: Float = 30,
        maxFrequency: Float = 1500
    ) -> PitchEstimate? {
        switch self {
        case .mpm:
            return Self.runMPM(samples, sampleRate, minFrequency, maxFrequency)
        case .yin:
            return YIN.detectPitch(samples: samples, sampleRate: sampleRate,
                                   minFrequency: minFrequency, maxFrequency: maxFrequency)
        case .hps:
            return HPS.detectPitch(samples: samples, sampleRate: sampleRate,
                                   minFrequency: minFrequency, maxFrequency: maxFrequency)
        case .ensemble:
            return Self.ensemble(samples, sampleRate, minFrequency, maxFrequency)
        }
    }

    // MARK: Helpers

    /// Run MPM with NO internal clarity gate (threshold 0) and adapt its result
    /// to the shared `PitchEstimate`. The detector applies the real clarity gate.
    private static func runMPM(_ samples: [Float], _ sampleRate: Double,
                               _ minF: Float, _ maxF: Float) -> PitchEstimate? {
        MPM.detectPitch(samples: samples, sampleRate: sampleRate,
                        minFrequency: minF, maxFrequency: maxF, clarityThreshold: 0)
            .map { PitchEstimate(frequency: $0.frequency, clarity: $0.clarity) }
    }

    /// Run MPM + YIN over the buffer and fuse their answers via `combine` (the
    /// pure, unit-tested decision rule), with HPS on call as the tie-breaker.
    ///
    /// WHY HPS IS LAZY: HPS only ever changes the outcome when MPM and YIN
    /// DISAGREE — in the (overwhelmingly common) agreement branch its answer is
    /// never consulted. Running its large FFT on every buffer, ~10×/second on
    /// the main actor, was the jank risk that originally kept it out of the
    /// ensemble. Passing it as an `@autoclosure` means the FFT runs ONLY on the
    /// rare disagreement frames — near-zero amortized cost, full tie-breaking
    /// benefit (octave errors are exactly where the two time-domain detectors
    /// split, and exactly where HPS's harmonic-series evidence is decisive).
    private static func ensemble(_ samples: [Float], _ sampleRate: Double,
                                 _ minF: Float, _ maxF: Float) -> PitchEstimate? {
        let mpm = runMPM(samples, sampleRate, minF, maxF)
        let yin = YIN.detectPitch(samples: samples, sampleRate: sampleRate,
                                  minFrequency: minF, maxFrequency: maxF)
        return combine(mpm: mpm, yin: yin,
                       hps: HPS.detectPitch(samples: samples, sampleRate: sampleRate,
                                            minFrequency: minF, maxFrequency: maxF))
    }

    /// The window (in cents) within which two detectors are treated as AGREEING.
    private static let agreementCents: Float = 40

    /// How close (in cents) HPS must be to MPM or YIN to be treated as corroborating
    /// it when those two disagree.
    private static let hpsCorroborationCents: Float = 60

    /// Absolute cents between two frequencies (0 if either is non-positive).
    private static func centsBetween(_ a: Float, _ b: Float) -> Float {
        guard a > 0, b > 0 else { return 0 }
        return abs(1200 * log2(a / b))
    }

    /// The PURE decision rule the ensemble applies to two detectors' answers,
    /// pulled out of `ensemble` so it can be unit-tested directly with synthetic
    /// estimates (forcing a real MPM/YIN *disagreement* from audio is impractical —
    /// they're both autocorrelation-family and tend to agree). `internal` for
    /// `@testable` access.
    ///
    ///   • Both fire & AGREE (within ~40 cents) → corroborated: BLEND the two
    ///     frequencies (weighted by clarity) for a result more accurate than either
    ///     alone, and nudge the confidence up. (HPS isn't needed here.)
    ///   • Both fire & DISAGREE (e.g. one made an octave error) → if `hps`
    ///     corroborates one of them (within ~60 cents, and closer to it than the
    ///     other), trust that one — HPS breaks the octave tie. Otherwise fall back
    ///     to the more confident detector.
    ///   • Only one fires → use it. Neither → nil.
    ///
    /// `hps` is an `@autoclosure`: the expression the caller passes (a full HPS
    /// run, with its big FFT) is evaluated ONLY if this rule actually reaches
    /// the disagreement branch and consults it — the agreement/single/neither
    /// paths never pay for it.
    static func combine(
        mpm: PitchEstimate?,
        yin: PitchEstimate?,
        hps: @autoclosure () -> PitchEstimate? = nil
    ) -> PitchEstimate? {
        switch (mpm, yin) {
        case let (m?, y?):
            if centsBetween(m.frequency, y.frequency) <= agreementCents {
                // Corroborated: a clarity-weighted average of the two agreeing
                // frequencies is more accurate than picking one (which could be
                // the less-accurate of the two by up to ~40 cents).
                let totalClarity = m.clarity + y.clarity
                let frequency = totalClarity > 0
                    ? (m.frequency * m.clarity + y.frequency * y.clarity) / totalClarity
                    : (m.frequency + y.frequency) / 2
                return PitchEstimate(frequency: frequency,
                                     clarity: min(1, max(m.clarity, y.clarity) + 0.1))
            }
            // Disagreement. Let HPS break the tie if it clearly sides with one.
            // (`hps()` is where the lazy HPS run actually happens.)
            if let hps = hps() {
                let dm = centsBetween(m.frequency, hps.frequency)
                let dy = centsBetween(y.frequency, hps.frequency)
                if dm <= hpsCorroborationCents, dm < dy { return m }
                if dy <= hpsCorroborationCents, dy < dm { return y }
            }
            // No HPS, or HPS corroborates neither → trust the more confident.
            return m.clarity >= y.clarity ? m : y
        case let (m?, nil): return m
        case let (nil, y?): return y
        case (nil, nil):    return nil
        }
    }
}
