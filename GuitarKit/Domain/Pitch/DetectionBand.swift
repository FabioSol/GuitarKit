//
//  DetectionBand.swift
//  GuitarKit
//
//  The tuning-aware frequency band for pitch detection — the "prior" the
//  selected tuning gives the detector.
//
//  WHY THIS EXISTS:
//  The detector used to search a fixed 30–1500 Hz and band-pass a fixed
//  65–1000 Hz regardless of what's being tuned. That wastes the strongest piece
//  of information the app has (it knows the target strings), and the fixed
//  65 Hz high-pass actually *attenuated* a 5-string bass low B (30.9 Hz) —
//  the very string the preprocessor exists to rescue.
//
//  Deriving the band from the active targets buys two things:
//    • the SEARCH RANGE clip below the lowest string makes an octave-down
//      error on that string mathematically impossible (the candidate lag is
//      simply never considered — stronger than filtering, which only
//      attenuates the evidence), and
//    • the FILTER CORNERS hug the tuning, so hum/rumble rejection tightens
//      for high-pitched instruments (ukulele, violin) instead of staying
//      tuned for guitar.
//
//  The margins are asymmetric on purpose:
//    • 5 semitones of FLAT margin — strings arrive flat far more often than
//      sharp (preset switches like Drop D → Standard leave 2 semitones; fresh
//      strings sag), and 5 stays comfortably under the 12 that would readmit
//      octave-down errors.
//    • 3 semitones of SHARP margin — strings are rarely wildly sharp (tension
//      and breakage risk deter it), and staying stingy here keeps a lower
//      string's 2nd harmonic from posing as a fundamental above the top string.
//
//  The LOW-PASS corner deliberately does NOT follow the sharp margin: the
//  detectors need the top string's 2nd/3rd harmonics for clarity and accuracy,
//  so it sits at ~3× the highest target instead (harmonic headroom). Only the
//  high-pass corner follows the band edge.
//
//  Pure value math — no audio, no UI — so it's unit-testable on its own.
//

import Foundation

/// A frequency band constraining pitch detection: the search range handed to
/// the algorithms plus the band-pass corners for the preprocessor.
///
/// `Equatable` so the detector can cheaply skip a re-apply when nothing
/// changed; `Sendable` because it's an immutable bundle of doubles.
nonisolated public struct DetectionBand: Equatable, Sendable {
    /// Lowest fundamental the algorithms will consider, in Hz.
    public let minFrequencyHz: Double
    /// Highest fundamental the algorithms will consider, in Hz.
    public let maxFrequencyHz: Double
    /// High-pass corner (hum/rumble out below this), in Hz.
    public let highPassHz: Double
    /// Low-pass corner (harmonics/hiss tamed above this), in Hz.
    public let lowPassHz: Double

    public init(minFrequencyHz: Double, maxFrequencyHz: Double,
                highPassHz: Double, lowPassHz: Double) {
        self.minFrequencyHz = minFrequencyHz
        self.maxFrequencyHz = maxFrequencyHz
        self.highPassHz = highPassHz
        self.lowPassHz = lowPassHz
    }

    // MARK: The two bands in use

    /// The unconstrained band — chromatic mode and the custom-tuning editor's
    /// capture-by-playing, where out-of-range notes are the whole point. Its
    /// corners follow the SAME rules as a tuning-derived band (high-pass at the
    /// low edge, low-pass with harmonic headroom over the ceiling) — there are
    /// no fixed filter corners anywhere anymore, only the derivation rule
    /// applied to different edges.
    public static let full = DetectionBand(
        minFrequencyHz: 30, maxFrequencyHz: 1500,
        highPassHz: 30, lowPassHz: 1500 * harmonicHeadroom
    )

    /// How far below the lowest target we still detect (semitones). Wide,
    /// because strings commonly arrive flat.
    static let flatMarginSemitones = 5.0
    /// How far above the highest target we still detect (semitones). Narrow,
    /// because strings are rarely wildly sharp.
    static let sharpMarginSemitones = 3.0
    /// The low-pass corner as a multiple of the highest target, so the top
    /// string keeps 2–3 harmonics for the detectors to lock onto.
    static let harmonicHeadroom = 3.0
    /// Absolute floor for the band's low edge, in Hz — keeps the algorithms'
    /// longest search lag well inside the analysis buffer.
    static let absoluteFloorHz = 20.0

    /// How far around the targets the band reaches. The defaults are the
    /// reasoned values in the header; the benchmark's parameter search
    /// (`PitchBench/tune.py`) varies them to test that reasoning.
    public struct Margins: Equatable, Sendable {
        public var flatSemitones = DetectionBand.flatMarginSemitones
        public var sharpSemitones = DetectionBand.sharpMarginSemitones
        public var harmonicHeadroom = DetectionBand.harmonicHeadroom
        public init() {}
    }

    /// Derive the band for a set of tuning targets (already capo-shifted —
    /// callers pass the session's *effective* targets). Returns `nil` for an
    /// empty target list (the placeholder tuning), which callers should treat
    /// as "no prior" and fall back to `.full`.
    public static func around(targets: [PitchTarget], margins: Margins = Margins()) -> DetectionBand? {
        let frequencies = targets.map(\.frequencyHz)
        guard let lowest = frequencies.min(), let highest = frequencies.max() else { return nil }
        return around(lowestHz: lowest, highestHz: highest, margins: margins)
    }

    /// The same derivation from just the lowest and highest target.
    public static func around(lowestHz lowest: Double, highestHz highest: Double,
                              margins: Margins = Margins()) -> DetectionBand? {
        guard lowest > 0, highest >= lowest else { return nil }

        // A semitone is a factor of 2^(1/12), so ± n semitones is × 2^(±n/12).
        let floor = max(absoluteFloorHz, lowest * pow(2, -margins.flatSemitones / 12))
        let ceiling = highest * pow(2, margins.sharpSemitones / 12)

        return DetectionBand(
            minFrequencyHz: floor,
            maxFrequencyHz: ceiling,
            // The high-pass follows the band's low edge exactly: everything we
            // intend to detect passes, everything below is hum/rumble.
            highPassHz: floor,
            // The low-pass keeps harmonic headroom instead of hugging the band
            // (see the header). The preprocessor clamps it to Nyquist itself.
            lowPassHz: highest * margins.harmonicHeadroom
        )
    }
}
