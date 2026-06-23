//
//  Scale.swift
//  GuitarKit — Harmony domain
//
//  A *scale* is an ordered set of pitch classes built up from a root by a fixed
//  pattern of intervals. The Scales tool (PRD stories 55–57) needs, for a chosen
//  root and scale type, the note set to light up on the fretboard. This file
//  defines the scale "recipes" as semitone offsets from the root and turns them
//  into concrete notes.
//
//  We deliberately keep scales as *interval recipes* (offsets in semitones from
//  the root) rather than hard-coding notes per key. That way every scale works
//  from every root for free, and the logic is trivially testable: "C major =
//  C D E F G A B", "A natural minor = A B C D E F G", etc.
//

import Foundation

/// The scale and mode catalogue required by the PRD: major, the three minors,
/// the two pentatonics, the blues scale, and the seven church modes.
///
/// Note: Ionian == major and Aeolian == natural minor. We still list the modes
/// separately because the UI presents them as their own choices, and naming
/// them documents the relationships.
public enum ScaleType: CaseIterable, Hashable, Sendable {
    case major                 // Ionian
    case naturalMinor          // Aeolian
    case harmonicMinor
    case melodicMinor          // ascending form (the jazz/"real" melodic minor)
    case majorPentatonic
    case minorPentatonic
    case blues                 // minor blues (minor pentatonic + ♭5)

    // The seven church modes, in their conventional order:
    case ionian
    case dorian
    case phrygian
    case lydian
    case mixolydian
    case aeolian
    case locrian

    /// The recipe: semitone offsets from the root, starting at 0 (the root
    /// itself) and ascending within one octave. These are the canonical
    /// definitions every music theory text agrees on.
    ///
    /// Reading a couple of them:
    ///  • major  = [0,2,4,5,7,9,11] → root, whole, whole, half, whole, whole,
    ///    whole (the "WWHWWWH" pattern, the half-steps being 3→4 and 7→8).
    ///  • natural minor = [0,2,3,5,7,8,10] → the relative major's pattern rotated
    ///    to start on the 6th degree (which is exactly what "relative minor"
    ///    means).
    public var semitoneOffsets: [Int] {
        switch self {
        case .major, .ionian:
            return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor, .aeolian:
            return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor:
            // Natural minor with a raised 7th (10 → 11) — gives that
            // augmented-second leap and the leading tone that natural minor
            // lacks.
            return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor:
            // Natural minor with BOTH 6th and 7th raised (8→9, 10→11) — like a
            // major scale with a lowered 3rd. (Ascending form; classical theory
            // descends as natural minor, but the tool uses the ascending set.)
            return [0, 2, 3, 5, 7, 9, 11]
        case .majorPentatonic:
            // Major scale minus its 4th and 7th (the two notes that create
            // half-step "tension") → 5 notes: 0,2,4,7,9.
            return [0, 2, 4, 7, 9]
        case .minorPentatonic:
            // Natural minor minus its 2nd and 6th → 5 notes: 0,3,5,7,10. (This
            // is the major pentatonic of the relative major, rotated.)
            return [0, 3, 5, 7, 10]
        case .blues:
            // Minor pentatonic plus the "blue note" ♭5 (6 semitones) → 6 notes.
            return [0, 3, 5, 6, 7, 10]
        case .dorian:
            // Minor-ish mode: natural minor with a raised 6th (8 → 9).
            return [0, 2, 3, 5, 7, 9, 10]
        case .phrygian:
            // Minor-ish mode with a lowered 2nd (2 → 1) — the "Spanish" colour.
            return [0, 1, 3, 5, 7, 8, 10]
        case .lydian:
            // Major-ish mode with a raised 4th (5 → 6) — the "bright" colour.
            return [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian:
            // Major-ish mode with a lowered 7th (11 → 10) — the "dominant" mode.
            return [0, 2, 4, 5, 7, 9, 10]
        case .locrian:
            // The darkest mode: lowered 2nd AND 5th → built on the 7th degree of
            // the major scale; its tonic triad is diminished.
            return [0, 1, 3, 5, 6, 8, 10]
        }
    }
}

/// A concrete scale: a root pitch class + a type. Asking it for its `notes`
/// applies the recipe to the root.
public struct Scale: Hashable, Sendable {
    public let root: PitchClass
    public let type: ScaleType

    public init(root: PitchClass, type: ScaleType) {
        self.root = root
        self.type = type
    }

    /// The scale's pitch classes, in ascending order starting on the root.
    /// This is just "transpose the root by each offset in the recipe."
    public var notes: [PitchClass] {
        type.semitoneOffsets.map { root.transposed(by: $0) }
    }

    /// The same notes as an unordered `Set`, for membership questions like
    /// "is this fret in the scale?" (the Scales tool's core query) and for
    /// order-independent equality in tests.
    public var pitchClassSet: Set<PitchClass> {
        Set(notes)
    }

    /// How many distinct notes the scale has (7 for diatonic scales/modes, 5 for
    /// pentatonics, 6 for blues). Handy sanity check.
    public var noteCount: Int { type.semitoneOffsets.count }
}
