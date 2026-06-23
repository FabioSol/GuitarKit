//
//  Note.swift
//  GuitarKit
//
//  The pure, deterministic core of the music domain.
//
//  This file has NO UIKit / SwiftUI / AVFoundation imports on purpose.
//  Everything here is plain value-type logic that we can unit-test in
//  isolation. Keeping the math separate from the UI is what makes the
//  app's "everything is tuning-aware" promise testable and trustworthy.
//

import Foundation

// MARK: - PitchClass

/// The twelve pitch classes of the chromatic scale (C, C#, D, ... B).
///
/// WHY AN ENUM?
/// A pitch class is a *closed set* of exactly 12 possibilities — there is no
/// 13th note name. Swift's `enum` is the perfect tool for "one value out of a
/// fixed list of named cases". Using an enum instead of, say, an `Int` or a
/// `String` means the compiler guarantees we can never construct an invalid
/// pitch class, and we get exhaustive `switch` checking for free.
///
/// `Int` raw values: by declaring `: Int` we give each case an underlying
/// integer (C = 0, C# = 1, ... B = 11). This mirrors how MIDI numbers semitones
/// upward from C, so the raw value doubles as "semitones above C", which makes
/// the MIDI conversion below trivial.
///
/// `CaseIterable` synthesizes an `allCases` array so callers (e.g. a chromatic
/// tuner naming any note) can iterate over all twelve.
///
/// `Comparable` lets us order pitch classes (C < C# < ... < B), handy for tests
/// and for sorting.
///
/// `Sendable` marks the type as safe to pass across concurrency boundaries —
/// trivially true for a simple value type, and good hygiene in modern Swift.
public enum PitchClass: Int, CaseIterable, Comparable, Sendable {
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

    /// Conformance to `Comparable`. The compiler can synthesize `==` for enums,
    /// but for ordering we implement `<` ourselves by comparing the raw Int
    /// values (semitones above C). `static func` means this operator belongs to
    /// the type, not to an instance.
    public static func < (lhs: PitchClass, rhs: PitchClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// A human-readable name using sharp spelling.
    ///
    /// WHY A COMPUTED PROPERTY?
    /// `name` has no stored memory of its own — it is *derived* from the case
    /// every time it's read. A computed property (a `var` with a `{ get }` body)
    /// expresses "this is a function of my state" without taking up storage.
    /// We expose sharps only for v1; enharmonic flat spelling (Db, Eb, ...) can
    /// be layered on later by the harmony slice without changing this core.
    public var name: String {
        switch self {
        case .c:      return "C"
        case .cSharp: return "C#"
        case .d:      return "D"
        case .dSharp: return "D#"
        case .e:      return "E"
        case .f:      return "F"
        case .fSharp: return "F#"
        case .g:      return "G"
        case .gSharp: return "G#"
        case .a:      return "A"
        case .aSharp: return "A#"
        case .b:      return "B"
        }
    }
}

// MARK: - Note

/// A specific musical pitch: a pitch class *plus* an octave (e.g. A4, E2).
///
/// WHY A STRUCT?
/// A `Note` is a small bundle of values with no identity — two A4s are
/// completely interchangeable. That's the textbook case for a `struct` (a
/// value type): it's copied on assignment, has automatic memberwise equality
/// when we ask for it, and can't be accidentally shared/mutated from two places
/// at once the way a `class` (reference type) could.
///
/// `Equatable`/`Hashable` let us compare notes and use them as dictionary keys
/// or set members (the fretboard/harmony slices will want this). `Sendable` is
/// again free safety for a pure value type.
///
/// OCTAVE NUMBERING: we use *scientific pitch notation*, where middle C is C4
/// and the A above it (the tuning reference) is A4 = MIDI 69. This is the most
/// common convention and the one the PRD's formula assumes.
public struct Note: Equatable, Hashable, Sendable {
    /// Which of the twelve notes (ignoring octave).
    public let pitchClass: PitchClass
    /// The scientific-pitch octave number (A4 = the 440 Hz reference octave).
    public let octave: Int

    /// The memberwise initializer.
    ///
    /// Swift would synthesize one automatically, but a `struct`'s synthesized
    /// init is `internal` by default — invisible outside this module. Because
    /// this is the public API other slices build on, we write an explicit
    /// `public init` so callers in the app target (and the tests) can create
    /// notes directly.
    public init(pitchClass: PitchClass, octave: Int) {
        self.pitchClass = pitchClass
        self.octave = octave
    }

    // MARK: MIDI conversion

    /// The MIDI note number for this pitch (e.g. A4 -> 69, C4 -> 60).
    ///
    /// THE MATH:
    /// MIDI numbers count semitones upward, with C(-1) = 0. So every octave adds
    /// 12, and within an octave the pitch class's raw value (0...11) is the
    /// offset from C. Scientific octave 4 corresponds to MIDI octave index 5
    /// (because C-1 is the zeroth MIDI octave), hence the `+ 1`:
    ///
    ///     midi = (octave + 1) * 12 + semitonesAboveC
    ///
    /// Quick check: A4 -> (4 + 1) * 12 + 9 = 60 + 9 = 69. Correct.
    public var midiNumber: Int {
        (octave + 1) * 12 + pitchClass.rawValue
    }

    /// Build a `Note` back from a MIDI number (the inverse of `midiNumber`).
    ///
    /// WHY A STATIC FACTORY INSTEAD OF AN INIT?
    /// Naming it `from(midiNumber:)` reads clearly at the call site
    /// (`Note.from(midiNumber: 69)`) and keeps the "decompose an Int" intent
    /// obvious. `static` means it's called on the type itself, not an instance,
    /// because there's no existing note to start from.
    ///
    /// THE MATH (inverse of above):
    ///   octave        = midi / 12 - 1     (integer division)
    ///   semitoneInOct = midi % 12         (remainder = pitch class)
    ///
    /// `%` on a non-negative Int is always 0...11, so the force-unwrapped
    /// `PitchClass(rawValue:)` is safe for any MIDI number >= 0. We clamp the
    /// remainder defensively for negative inputs so we never crash.
    public static func from(midiNumber: Int) -> Note {
        // Swift's `%` can return a negative remainder for negative operands,
        // which would be an invalid PitchClass raw value. We normalize into the
        // 0...11 range with the classic ((x % 12) + 12) % 12 trick.
        let semitone = ((midiNumber % 12) + 12) % 12
        // Integer division rounds toward zero, so we use floored division to get
        // the right octave for negative MIDI numbers too. For the ranges this
        // app cares about (bass ~28 up to high guitar ~88) it's plain `/`.
        let octave = Int(floor(Double(midiNumber) / 12.0)) - 1
        // `PitchClass(rawValue:)` returns an Optional because not every Int is a
        // valid case — but we just guaranteed `semitone` is 0...11, so the
        // force-unwrap (`!`) is provably safe here.
        return Note(pitchClass: PitchClass(rawValue: semitone)!, octave: octave)
    }

    /// A display name like "A4" or "C#2".
    public var name: String {
        "\(pitchClass.name)\(octave)"
    }
}
