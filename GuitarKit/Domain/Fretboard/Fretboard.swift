//
//  Fretboard.swift
//  GuitarKit — Fretboard domain
//
//  The PURE, tuning-aware fretboard: given a set of open-string notes and a capo,
//  it answers "what note sounds at (string S, fret F)?" — the foundation the
//  Scales tool (and later chord voicings) light up on. No SwiftUI here, so the
//  mapping is unit-testable in isolation (PRD: "fretboard mapping is covered by
//  unit tests").
//
//  THE MODEL: a guitar string raised at fret F sounds F semitones above its open
//  pitch. A capo at fret N raises every OPEN string by N semitones first, and the
//  board's "fret 0" is then the capo'd open string. So:
//
//      note(string, fret) = (capo-raised open note) + fret  semitones
//

import Foundation

/// A tuning-aware fretboard.
///
/// `struct` because it's immutable value data derived from a tuning + capo — two
/// fretboards with the same strings are interchangeable. `Sendable` rides along.
public struct Fretboard: Sendable {

    /// The open-string notes, low → high (string 0 = lowest).
    public let openStrings: [Note]
    /// The capo (semitone shift of every open string). `.none` = no capo.
    public let capo: Capo
    /// How many frets the board spans (fret 0 = open).
    public let fretCount: Int

    public init(openStrings: [Note], capo: Capo = .none, fretCount: Int = 15) {
        self.openStrings = openStrings
        self.capo = capo
        self.fretCount = max(0, fretCount)
    }

    /// Convenience: build from a `Tuning`'s strings.
    public init(tuning: Tuning, capo: Capo = .none, fretCount: Int = 15) {
        self.init(openStrings: tuning.strings, capo: capo, fretCount: fretCount)
    }

    /// Number of strings on this board.
    public var stringCount: Int { openStrings.count }

    /// The note sounding at `(string, fret)`, or `nil` for an out-of-range index.
    /// Fret 0 is the (capo-raised) open string; each higher fret adds a semitone.
    public func note(string: Int, fret: Int) -> Note? {
        guard openStrings.indices.contains(string), fret >= 0, fret <= fretCount else { return nil }
        // The capo raises the open string first; the fret then adds on top.
        let capoOpen = capo.transpose(openStrings[string])
        return Note.from(midiNumber: capoOpen.midiNumber + fret)
    }
}
