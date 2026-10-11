//
//  PitchCalculator.swift
//  GuitarKit
//
//  The heart of the tuning domain: turning a musical note (plus the player's
//  calibration choices) into the exact frequency to tune to.
//
//  PRD invariant — "Frequency is always derived, never stored":
//
//      target = referenceA · 2^((midi − 69) / 12) · 2^(cents / 1200)
//
//  Pure math — no UI, no audio.
//

import Foundation

/// A computed tuning target: the note that should sound and the frequency it
/// should sound at. This is the value the tuning-session and tone-generator
/// slices will consume.
///
/// `struct` because it's an immutable bundle of results. `Equatable`/`Sendable`
/// for testing and safe sharing.
nonisolated public struct PitchTarget: Equatable, Sendable {
    /// The note that sounds at this target (already capo-shifted, if any).
    public let note: Note
    /// The frequency to tune to, in Hertz (includes any temperament sweetening).
    public let frequencyHz: Double
    /// The index of the string this target belongs to (0-based, in tuning order).
    public let stringIndex: Int

    public init(note: Note, frequencyHz: Double, stringIndex: Int) {
        self.note = note
        self.frequencyHz = frequencyHz
        self.stringIndex = stringIndex
    }
}

/// Derives frequencies from notes given a calibration context.
///
/// WHY A SEPARATE CALCULATOR TYPE (not methods on `Note`)?
/// The frequency of a note isn't an intrinsic property of the note — it depends
/// on the *player's* choices: reference pitch, temperament, and capo. Bundling
/// those choices here keeps `Note` a clean musical value and gives the rest of
/// the app one obvious place that owns the PRD formula. Centralizing it also
/// means there's exactly one implementation to unit-test.
///
/// `referenceA` and `temperament` are stored configuration. `temperament` is
/// declared as the *protocol* type `any Temperament`, not a concrete struct —
/// that's the polymorphism seam: the calculator works with equal temperament
/// today and any sweetened profile later, unchanged.
nonisolated public struct PitchCalculator: Sendable {
    public let referenceA: ReferencePitch
    public let temperament: any Temperament

    /// - Parameters:
    ///   - referenceA: A4 calibration; defaults to concert pitch (440 Hz).
    ///   - temperament: tuning system; defaults to equal temperament (no sweetening).
    public init(
        referenceA: ReferencePitch = .standard,
        temperament: any Temperament = EqualTemperament()
    ) {
        self.referenceA = referenceA
        self.temperament = temperament
    }

    // MARK: Core formula

    /// The pure, context-free frequency for a MIDI number with an extra cent
    /// offset — the literal PRD formula, isolated so it's trivially testable.
    ///
    /// THE MATH, TERM BY TERM:
    ///   • `referenceA.hertz`            — the anchor: frequency of A4 (MIDI 69)
    ///   • `2^((midi − 69) / 12)`        — equal temperament: each of the 12
    ///                                     semitones multiplies frequency by the
    ///                                     twelfth root of 2, so being `n`
    ///                                     semitones from A4 multiplies by 2^(n/12)
    ///   • `2^(cents / 1200)`            — fine sweetening: 1200 cents per octave,
    ///                                     so `c` cents multiplies by 2^(c/1200)
    ///
    /// `pow(2, x)` is C's power function from Foundation. We pass `Double`s so
    /// the division `(midi − 69)/12` is fractional, not integer.
    public func frequency(midiNumber: Int, centOffset: Double = 0) -> Double {
        let semitonesFromA4 = Double(midiNumber - 69)
        let equalTemperedRatio = pow(2.0, semitonesFromA4 / 12.0)
        let centRatio = pow(2.0, centOffset / 1200.0)
        return referenceA.hertz * equalTemperedRatio * centRatio
    }

    /// Frequency for a `Note` (convenience over the MIDI overload).
    public func frequency(of note: Note, centOffset: Double = 0) -> Double {
        frequency(midiNumber: note.midiNumber, centOffset: centOffset)
    }

    // MARK: Targets for a whole tuning

    /// Compute the tuning target for a single open string, folding in capo shift
    /// and the temperament's per-string sweetening.
    ///
    /// ORDER OF OPERATIONS:
    ///   1. capo raises the open note by N semitones (musical transposition)
    ///   2. look up this string's cent offset from the temperament
    ///   3. derive the frequency from the shifted note + offset
    ///
    /// - Parameters:
    ///   - note: the open-string note as defined by the tuning.
    ///   - stringIndex: 0-based position in the tuning (drives sweetening lookup).
    ///   - stringCount: total strings (some sweetened profiles need it).
    ///   - capo: capo position; defaults to none.
    public func target(
        for note: Note,
        stringIndex: Int,
        stringCount: Int,
        capo: Capo = .none
    ) -> PitchTarget {
        let sounding = capo.transpose(note)
        let cents = temperament.centOffset(forStringIndex: stringIndex, stringCount: stringCount)
        let hz = frequency(of: sounding, centOffset: cents)
        return PitchTarget(note: sounding, frequencyHz: hz, stringIndex: stringIndex)
    }

    /// Compute targets for an entire set of open strings (a tuning) at once.
    ///
    /// WHY GENERICS HERE? We don't — we take a concrete `[Note]`. But note the
    /// shape: `enumerated()` pairs each note with its index, and `map`
    /// transforms each pair into a `PitchTarget`. `map` is a higher-order
    /// function: "apply this transform to every element, collect the results",
    /// the functional alternative to a manual `for` loop with an accumulator.
    public func targets(for strings: [Note], capo: Capo = .none) -> [PitchTarget] {
        let count = strings.count
        return strings.enumerated().map { index, note in
            target(for: note, stringIndex: index, stringCount: count, capo: capo)
        }
    }

    // MARK: Deviation (how flat/sharp a heard pitch is)

    /// How many **cents** `detectedHz` is away from `targetHz`.
    /// Positive = sharp (too high), negative = flat (too low) — matching the
    /// PRD's tuner feedback ("which way to turn the peg").
    ///
    /// THE MATH: cents between two frequencies is `1200 · log2(f1 / f2)`. We use
    /// `log2` (base-2 log) because an octave is a 2:1 ratio and equals exactly
    /// 1200 cents. This is the inverse of the `2^(cents/1200)` factor above.
    ///
    /// `static` because it depends only on its two inputs, not on the
    /// calculator's calibration — so it reads naturally as `PitchCalculator
    /// .cents(from:to:)` and can be reused anywhere.
    public static func cents(from detectedHz: Double, to targetHz: Double) -> Double {
        // Guard against non-positive OR non-finite inputs that would make log2
        // undefined or emit NaN/Inf (a detector can momentarily report 0 Hz
        // during silence, or a bad estimate can be ±Inf/NaN).
        guard detectedHz > 0, targetHz > 0, detectedHz.isFinite, targetHz.isFinite else { return 0 }
        return 1200.0 * log2(detectedHz / targetHz)
    }

    // MARK: Nearest note (frequency → note, for the chromatic readout)

    /// Given a *detected* frequency, find the nearest equal-tempered note and how
    /// many cents off it is. This is the INVERSE of the core formula — used by
    /// the pitch detector's raw/chromatic readout to answer "what note is this,
    /// and how flat/sharp?" without needing a pre-chosen tuning target.
    ///
    /// THE MATH (inverting `freq = referenceA · 2^((midi−69)/12)`):
    ///   • Solve for a *fractional* MIDI number:
    ///         midiExact = 69 + 12 · log2(freq / referenceA)
    ///     e.g. exactly 440 Hz → 69.0; a quarter-tone sharp of A4 → 69.5.
    ///   • Round to the nearest whole MIDI number → the closest real note.
    ///   • The cent offset is how far the frequency sits from THAT note's own
    ///     equal-tempered frequency (reusing `cents(from:to:)`), so it's exact
    ///     rather than a rounding-of-the-rounding.
    ///
    /// NOTE: this readout is plain equal temperament — it deliberately ignores
    /// per-string sweetening, because a chromatic "what note am I hearing?"
    /// display has no notion of which string you meant. The targeted tuning
    /// session (a later slice) is where sweetened offsets come back in.
    ///
    /// - Returns: the nearest `Note` and the signed cent offset (positive =
    ///   sharp, negative = flat), or `nil` for a non-positive frequency.
    public func nearestNote(toFrequency hz: Double) -> (note: Note, centOffset: Double)? {
        // Reject non-positive AND non-finite input: `+Inf` would make `midiExact`
        // infinite and `Int(.rounded())` TRAP. (`hz > 0` alone lets `+Inf` through;
        // `NaN > 0` is already false.)
        guard hz > 0, hz.isFinite else { return nil }

        // Fractional MIDI number, then round to the closest actual note.
        let midiExact = 69.0 + 12.0 * log2(hz / referenceA.hertz)
        let nearestMidi = Int(midiExact.rounded())

        let note = Note.from(midiNumber: nearestMidi)
        // Cents between the heard frequency and that note's equal-tempered pitch.
        let centOffset = PitchCalculator.cents(from: hz, to: frequency(midiNumber: nearestMidi))
        return (note, centOffset)
    }
}
