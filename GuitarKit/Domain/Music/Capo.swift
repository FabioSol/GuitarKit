//
//  Capo.swift
//  GuitarKit
//
//  A capo clamps across the fretboard at fret N, raising every open string by
//  N semitones. In the tuning domain this is simply "shift all targets up by N",
//  with N clamped to 0...12 (PRD story 24 + Picker/persistence notes).
//
//  Pure value logic — no UI, no audio.
//

import Foundation

/// Represents a capo position as a semitone shift, clamped to 0...12.
///
/// WHY A TYPE AND NOT JUST AN `Int`?
/// Same reasoning as `ReferencePitch`: by funneling capo creation through one
/// initializer that clamps, we guarantee no part of the app ever sees a capo at
/// fret -3 or fret 20. Fret 0 means "no capo". The 12-fret ceiling matches the
/// PRD ("clamped 0–12") — beyond an octave a capo is musically pointless on
/// guitar.
///
/// `Equatable`/`Hashable`/`Sendable` for comparison, persistence, and safety.
public struct Capo: Equatable, Hashable, Sendable {
    /// Bounds for the semitone shift. `static` = belongs to the type.
    public static let minFret = 0
    public static let maxFret = 12

    /// The convenient "no capo" value, used as the default everywhere.
    public static let none = Capo(fret: 0)

    /// The validated fret (= number of semitones to raise every string).
    public let fret: Int

    /// Create a capo, clamping `fret` into 0...12.
    public init(fret: Int) {
        self.fret = Swift.max(Self.minFret, Swift.min(Self.maxFret, fret))
    }

    /// Whether a capo is actually engaged (fret > 0). Handy for UI ("show the
    /// +2 counter only when active") and for skipping work when there's none.
    public var isEngaged: Bool { fret > Self.minFret }

    /// Apply this capo to a note, returning the note that now sounds when the
    /// string is played open. A shift of N semitones is just `+N` on the MIDI
    /// number, then convert back to a `Note`.
    ///
    /// Example: low E (E2, MIDI 40) with a capo at fret 2 -> MIDI 42 -> F#2.
    public func transpose(_ note: Note) -> Note {
        Note.from(midiNumber: note.midiNumber + fret)
    }
}
