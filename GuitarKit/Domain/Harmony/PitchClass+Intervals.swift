//
//  PitchClass+Intervals.swift
//  GuitarKit — Harmony domain
//
//  INTEGRATION NOTE:
//  The Harmony domain originally defined its own minimal `PitchClass` so it
//  could be built and tested in isolation. At integration we reconciled it with
//  the canonical `PitchClass` from the Music domain (see Domain/Music/Note.swift)
//  — the two were identical in cases and raw values (C = 0 ... B = 11). The only
//  thing Harmony added was two interval helpers, which we keep here as an
//  *extension* on the shared type. Extensions let us bolt behavior onto an
//  existing type without touching its original definition — so Music owns the
//  type, and Harmony contributes the interval arithmetic it needs.
//

import Foundation

extension PitchClass {
    /// Move this pitch class up (or, with a negative number, down) by a number
    /// of semitones, wrapping around the octave.
    ///
    /// Example: `PitchClass.b.transposed(by: 1)` is `.c` (B up one semitone wraps
    /// back to C). This is the workhorse of the harmony layer: chords and scales
    /// are just "the root, transposed by each interval in a recipe."
    ///
    /// The maths: add the offset to our raw value, then `% 12` to wrap into
    /// 0...11. Swift's `%` can return a negative for negative inputs
    /// (-1 % 12 == -1), which is not a valid raw value, so we add 12 and `%`
    /// again to force it positive.
    public func transposed(by semitones: Int) -> PitchClass {
        let wrapped = ((rawValue + semitones) % 12 + 12) % 12
        // `wrapped` is guaranteed to be in 0...11, so the failable
        // `init(rawValue:)` can be force-unwrapped safely.
        return PitchClass(rawValue: wrapped)!
    }

    /// The distance in semitones from another pitch class *up* to this one,
    /// always expressed as 0...11.
    ///
    /// Example: from C up to E is 4; from E up to C is 8 (keep going up and wrap).
    public func semitoneDistance(from other: PitchClass) -> Int {
        return ((rawValue - other.rawValue) % 12 + 12) % 12
    }
}
