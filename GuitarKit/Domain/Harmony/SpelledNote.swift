//
//  SpelledNote.swift
//  GuitarKit — Harmony domain
//
//  A `PitchClass` knows "which of the 12 keys on a piano" a note is, but it does
//  NOT know how to *spell* it. The black key between F and G is one pitch class,
//  but musicians call it "F#" in the key of G and "Gb" in the key of Db — same
//  sound, different *name*. That choice of name is what a *key signature* is all
//  about, and getting it right is the difference between a correct music app and
//  one that shows nonsense like "the key of F# has a Cb in it... or is it B?".
//
//  So we introduce a richer type that carries a *letter* (A–G) and an
//  *accidental* (how many sharps/flats), from which the pitch class is derived.
//

import Foundation

/// The seven natural letter names. The raw `Int` is the letter's *position in
/// the musical alphabet* starting at C (C=0, D=1, ... B=6). We start at C, not
/// A, to stay consistent with `PitchClass` (where C is also 0); it makes the
/// "next letter after B wraps to C" logic line up cleanly.
public enum Letter: Int, CaseIterable, Hashable, Sendable {
    case c = 0, d, e, f, g, a, b

    /// The pitch class of this letter with *no* accidental (the "natural").
    /// C→C, D→D, E→E, F→F, G→G, A→A, B→B in semitones-above-C terms:
    /// C=0, D=2, E=4, F=5, G=7, A=9, B=11. These gaps encode the white-key
    /// pattern of a piano (two semitones between most letters, but only one
    /// between E–F and B–C).
    public var naturalPitchClass: PitchClass {
        switch self {
        case .c: return .c
        case .d: return .d
        case .e: return .e
        case .f: return .f
        case .g: return .g
        case .a: return .a
        case .b: return .b
        }
    }

    /// The single-character name ("C", "D", ...). Used to build display text.
    public var name: String {
        switch self {
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .a: return "A"
        case .b: return "B"
        }
    }

    /// The letter `n` steps further along the alphabet, wrapping past B→C.
    /// Used when building a scale, where each successive note takes the *next*
    /// letter (so a C-major scale is C D E F G A B — every letter exactly once).
    public func advanced(by n: Int) -> Letter {
        let wrapped = ((rawValue + n) % 7 + 7) % 7
        return Letter(rawValue: wrapped)!
    }
}

/// A note *spelled* as a letter plus an accidental offset in semitones.
/// `accidental == 0` is natural, `+1` is sharp, `-1` is flat, `+2` is
/// double-sharp, `-2` is double-flat. We allow doubles because some correct key
/// signatures and chords genuinely need them (e.g. the vii° triad of certain
/// keys), even if v1's keys themselves won't.
public struct SpelledNote: Hashable, Sendable {
    public let letter: Letter
    /// Semitone offset from the natural: 0 natural, +1 sharp, -1 flat, etc.
    public let accidental: Int

    public init(letter: Letter, accidental: Int = 0) {
        self.letter = letter
        self.accidental = accidental
    }

    /// The pitch class this spelling actually sounds as: take the letter's
    /// natural pitch class and shift it by the accidental. This is the bridge
    /// back to the "12 keys on a piano" world, and lets us assert that, say,
    /// "Gb" and "F#" are the *same* `PitchClass` even though they're different
    /// `SpelledNote`s.
    public var pitchClass: PitchClass {
        letter.naturalPitchClass.transposed(by: accidental)
    }

    /// Human-readable name: the letter followed by Unicode sharp/flat symbols.
    /// We use the proper musical glyphs (♯ ♭ 𝄪 𝄫) rather than ASCII # / b so the
    /// UI layer can show them directly. The repeated-symbol approach handles
    /// double accidentals naturally.
    public var name: String {
        let symbol: String
        switch accidental {
        case let a where a > 0:
            symbol = String(repeating: "♯", count: a)
        case let a where a < 0:
            symbol = String(repeating: "♭", count: -a)
        default:
            symbol = ""
        }
        return letter.name + symbol
    }
}
