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
public struct PitchEstimate: Equatable, Sendable {
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
public enum PitchAlgorithm: String, CaseIterable, Sendable {
    /// McLeod Pitch Method — the NSDF-based detector (good octave resistance).
    case mpm
    /// YIN — the cumulative-mean-normalized-difference detector (often steadier
    /// on guitar low strings).
    case yin
    /// Run BOTH and cross-check — most robust, ~2× the work.
    case ensemble

    /// A short label for the picker.
    public var label: String {
        switch self {
        case .mpm:      return "MPM"
        case .yin:      return "YIN"
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

    /// Combine MPM + YIN:
    ///   • Both fire & AGREE (within ~40 cents) → corroborated: BLEND the two
    ///     frequencies (weighted by clarity) for a more accurate result than
    ///     either alone, and nudge the confidence up.
    ///   • Both fire & DISAGREE (e.g. one made an octave error) → trust the more
    ///     confident detector.
    ///   • Only one fires → use it.
    private static func ensemble(_ samples: [Float], _ sampleRate: Double,
                                 _ minF: Float, _ maxF: Float) -> PitchEstimate? {
        let mpm = runMPM(samples, sampleRate, minF, maxF)
        let yin = YIN.detectPitch(samples: samples, sampleRate: sampleRate,
                                  minFrequency: minF, maxFrequency: maxF)

        switch (mpm, yin) {
        case let (m?, y?):
            let cents = abs(1200 * log2(m.frequency / y.frequency))
            if cents <= 40 {
                // Corroborated: a clarity-weighted average of the two agreeing
                // frequencies is more accurate than picking one (which could be
                // the less-accurate of the two by up to ~40 cents).
                let totalClarity = m.clarity + y.clarity
                let frequency = totalClarity > 0
                    ? (m.frequency * m.clarity + y.frequency * y.clarity) / totalClarity
                    : (m.frequency + y.frequency) / 2
                return PitchEstimate(frequency: frequency,
                                     clarity: min(1, max(m.clarity, y.clarity) + 0.1))
            } else {
                return m.clarity >= y.clarity ? m : y
            }
        case let (m?, nil): return m
        case let (nil, y?): return y
        case (nil, nil):    return nil
        }
    }
}
