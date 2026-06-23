//
//  Chord.swift
//  GuitarKit — Harmony domain
//
//  A concrete chord = a root pitch class + a quality. It resolves to a set of
//  pitch classes by applying the quality's interval recipe to the root. This is
//  what the Chords tool (PRD stories 52–54) consumes to know *which notes* a
//  chord contains before a voicing engine decides *where* to play them.
//

import Foundation

/// A chord as a root + quality. (We keep the root as a `PitchClass`, not a
/// spelled note, because at this layer we only care which pitches sound; the
/// fretboard/voicing layer and the label layer can add spelling later. This is
/// the local-representation simplification flagged for integration.)
public struct Chord: Hashable, Sendable {
    public let root: PitchClass
    public let quality: ChordQuality

    public init(root: PitchClass, quality: ChordQuality) {
        self.root = root
        self.quality = quality
    }

    /// The chord's notes in "stacked" order (root first, then up through the
    /// recipe). Because the recipe offsets can exceed an octave (for 9ths/11ths/
    /// 13ths), `transposed(by:)` wraps them back into a single octave's worth of
    /// twelve pitch classes — so the 9th of C (offset 14) correctly becomes D,
    /// the same pitch class as the 2nd, just conceptually an octave higher.
    public var notes: [PitchClass] {
        quality.semitoneOffsets.map { root.transposed(by: $0) }
    }

    /// The chord's notes as an unordered, de-duplicated `Set`. This is the right
    /// type for "does the chord contain this note?" questions and for
    /// order-independent equality in tests. (De-duplication matters: a voicing
    /// might double the root, but as a *pitch-class set* a chord lists each note
    /// once.)
    public var pitchClassSet: Set<PitchClass> {
        Set(notes)
    }

    /// Whether a given pitch class is one of the chord's tones — the membership
    /// query the fretboard highlighter will lean on.
    public func contains(_ pitchClass: PitchClass) -> Bool {
        pitchClassSet.contains(pitchClass)
    }
}
