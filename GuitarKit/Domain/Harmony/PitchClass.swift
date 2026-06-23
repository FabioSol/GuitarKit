//
//  PitchClass.swift
//  GuitarKit — Harmony domain
//
//  A *pitch class* is a note name without an octave: C, C#, D, ... B.
//  There are exactly 12 of them in 12-tone equal temperament, and they
//  repeat every octave (the C in "middle C" and the C an octave up are the
//  same pitch class). This is the atom the whole harmony layer is built from.
//
//  IMPORTANT (integration note for future-me):
//  A sibling "Music" domain model is being built in parallel under
//  GuitarKit/Domain/Music/ and will very likely have its own richer note /
//  pitch-class type (with octaves, MIDI numbers, frequency derivation, etc.).
//  To keep this Harmony module self-contained and buildable on its own, we
//  define our OWN minimal pitch-class type here. At integration time these two
//  representations should be reconciled (probably by having Harmony depend on
//  the Music type, or by providing a bridging initializer). Nothing else in
//  this module assumes anything about octaves or frequencies — only the 12
//  pitch classes and the integer distances ("semitones") between them.
//

import Foundation

/// One of the twelve pitch classes in 12-tone equal temperament.
///
/// We model this as an `enum` with an explicit `Int` *raw value* equal to the
/// number of semitones above C. Why C = 0? Because that is the overwhelmingly
/// common convention in music software (and it lines up with MIDI, where C is
/// the "0" of each octave). Using an enum (instead of a bare `Int`) means the
/// compiler guarantees a value is always a *valid* pitch class — you can never
/// accidentally construct pitch class 13.
///
/// `Int` raw type: lets us convert to/from the semitone number cheaply.
/// `CaseIterable`: auto-generates `PitchClass.allCases`, handy for tests and
/// for building chromatic scales.
/// `Hashable`: lets us put pitch classes in a `Set` (used heavily below to
/// compare "note sets" without caring about order or duplicates).
/// `Sendable`: this is an immutable value type with no reference semantics, so
/// it is safe to pass across concurrency boundaries; declaring it documents and
/// enforces that.
public enum PitchClass: Int, CaseIterable, Hashable, Sendable {
    case c = 0      // C
    case cSharp     // C# / Db
    case d          // D
    case dSharp     // D# / Eb
    case e          // E
    case f          // F
    case fSharp     // F# / Gb
    case g          // G
    case gSharp     // G# / Ab
    case a          // A
    case aSharp     // A# / Bb
    case b          // B

    /// Move this pitch class up (or, with a negative number, down) by a number
    /// of semitones, wrapping around the octave.
    ///
    /// Example: `PitchClass.b.transposed(by: 1)` is `.c` (B up one semitone
    /// wraps back to C). This single helper is the workhorse of the whole
    /// module: chords and scales are just "the root, transposed by each
    /// interval in a recipe."
    ///
    /// The maths: we add the semitone offset to our raw value, then take it
    /// modulo 12 to wrap into the 0...11 range. Swift's `%` can return a
    /// negative result for negative inputs (e.g. -1 % 12 == -1), which is not a
    /// valid raw value, so we add 12 and take `%` again to force it positive.
    public func transposed(by semitones: Int) -> PitchClass {
        let wrapped = ((rawValue + semitones) % 12 + 12) % 12
        // `PitchClass(rawValue:)` is a *failable* initializer (it returns an
        // optional, because an arbitrary Int might not be a valid case). We've
        // just guaranteed `wrapped` is in 0...11, so force-unwrapping with `!`
        // is safe here — there is no Int in that range without a matching case.
        return PitchClass(rawValue: wrapped)!
    }

    /// The distance in semitones from another pitch class *up* to this one,
    /// always expressed as 0...11.
    ///
    /// Example: from C up to E is 4 semitones; from E up to C is 8 (you keep
    /// going up and wrap around the octave). This is "interval class" style
    /// arithmetic and is handy when reasoning about chord/scale membership.
    public func semitoneDistance(from other: PitchClass) -> Int {
        return ((rawValue - other.rawValue) % 12 + 12) % 12
    }
}
