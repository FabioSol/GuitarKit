//
//  ChordVoicing.swift
//  GuitarKit — Harmony domain
//
//  A *voicing* is the concrete "where do my fingers go" for a chord: one fret
//  choice per string. The pure `Chord` type (Chord.swift) only knows WHICH
//  pitch classes a chord contains; a `ChordVoicing` knows WHERE on the neck to
//  play them. Splitting these two ideas is deliberate — the same C-major chord
//  has many shapes (open, barre at the 3rd, up at the 8th…), and each of those
//  shapes is a different `ChordVoicing`.
//
//  Like the rest of `Domain/`, this file has NO SwiftUI / AVFoundation imports.
//  It's plain value-type logic so the voicing engine and its shapes can be
//  unit-tested in isolation (the spec asks for exactly that).
//

import Foundation

/// One playable chord shape: a per-string fret assignment.
///
/// WHY A STRUCT (value type)?
/// A voicing is a small, identity-less bundle of numbers — two "x32010" shapes
/// are completely interchangeable. That's the textbook case for a `struct`. It's
/// copied on assignment and gets synthesized `Hashable`/`Equatable` for free, so
/// tests can compare two voicings directly and the UI can use one as a SwiftUI
/// identity. `Sendable` rides along because every stored value is itself a pure
/// value type, so a voicing is safe to pass across actors.
///
/// THE REPRESENTATION — `frets: [Int?]`:
///   • The array index IS the string index, low → high (string 0 = lowest),
///     matching `Fretboard`/`Tuning`'s low→high convention everywhere else in
///     the app. Keeping one consistent ordering is what lets "string 2" mean the
///     same thing across the engine, the generator, and the view.
///   • Each element is an *optional* `Int`:
///       – `nil`  → that string is MUTED / not played (the "x" in chord boxes).
///       – `0`    → that string is played OPEN (the "o" in chord boxes).
///       – `n`    → that string is fretted at fret `n`.
///   This single type cleanly captures all three states a string can be in,
///   without a parallel "is this string muted?" array to keep in sync.
public struct ChordVoicing: Sendable, Hashable {

    /// Per-string fret choices, low → high. `nil` = muted, `0` = open, `n` = fret.
    public let frets: [Int?]

    public init(frets: [Int?]) {
        self.frets = frets
    }

    // MARK: - Derived facts about the shape

    /// The indices of the strings that actually sound (i.e. not muted). Handy for
    /// playback (we only strum the strings that ring) and for the diagram.
    public var soundingStringIndices: [Int] {
        // `enumerated()` pairs each fret with its string index; we keep only the
        // pairs whose fret is non-nil, then map back to just the index.
        frets.enumerated().compactMap { index, fret in fret == nil ? nil : index }
    }

    /// The lowest FRET NUMBER actually fingered (ignoring muted strings and open
    /// strings). `nil` if the whole shape is open/muted (no fingered note at all).
    ///
    /// WHY IGNORE OPEN STRINGS (fret 0)?
    /// "How far up the neck is this shape?" is about where your hand sits. An open
    /// string isn't under a finger, so a shape like x32010 (open high E and B)
    /// "lives" at fret 2–3, not fret 0. The voicing generator uses this to tell
    /// alternates apart ("is this shape higher up the neck than that one?").
    public var lowestFrettedFret: Int? {
        // `compactMap` drops the `nil` (muted) strings; we then keep only the
        // genuinely fingered frets (> 0) and take the minimum.
        frets.compactMap { $0 }.filter { $0 > 0 }.min()
    }

    /// The highest fret number used anywhere in the shape (open strings count as
    /// 0). `nil` only if every string is muted. With `lowestFrettedFret` this
    /// describes the shape's fret SPAN, which a playability check can bound.
    public var highestFret: Int? {
        frets.compactMap { $0 }.max()
    }

    /// How many strings are muted in this shape — a rough "sparseness" signal the
    /// view-model can use to decide a generated shape is too thin and fall back to
    /// the curated library.
    public var mutedStringCount: Int {
        frets.filter { $0 == nil }.count
    }

    // MARK: - Projecting the shape onto a real board

    /// The actual sounding notes of this voicing on a given `Fretboard`, low →
    /// high, skipping muted strings.
    ///
    /// WHY TAKE A `Fretboard` (rather than store notes)?
    /// A voicing is just fret NUMBERS — the pitches depend entirely on the tuning
    /// and capo, which live in the `Fretboard`. The same x32010 shape sounds a C
    /// chord in standard tuning but something else in Drop D. Passing the board in
    /// keeps the voicing tuning-agnostic and makes "what does this shape sound
    /// like HERE?" the board's job, exactly as the engine intends.
    ///
    /// `compactMap` does double duty: it skips muted strings (we `return nil` for
    /// them) AND it unwraps `fretboard.note(...)`'s own optional (out-of-range
    /// frets), so the result is a clean `[Note]` with no holes.
    public func playedNotes(on fretboard: Fretboard) -> [Note] {
        frets.enumerated().compactMap { stringIndex, fret in
            guard let fret else { return nil }          // muted string → skip
            return fretboard.note(string: stringIndex, fret: fret)
        }
    }

    /// The pitch CLASSES this voicing sounds on a board (de-duplicated), as a set.
    /// This is what a test means by "does this shape only contain chord tones?":
    /// compare this set against `chord.pitchClassSet`.
    public func playedPitchClasses(on fretboard: Fretboard) -> Set<PitchClass> {
        Set(playedNotes(on: fretboard).map(\.pitchClass))
    }
}
