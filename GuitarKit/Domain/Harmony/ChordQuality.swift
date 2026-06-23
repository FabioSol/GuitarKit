//
//  ChordQuality.swift
//  GuitarKit — Harmony domain
//
//  A *chord quality* is the "flavour" of a chord independent of its root:
//  major, minor, dominant 7th, major 7th, diminished, suspended, and so on.
//  Like scales, we define each quality as a recipe of semitone offsets from the
//  root. "C major" is then just "root C, apply the major recipe → C E G."
//
//  This is the "rich quality set" the PRD calls for (stories 52, and the Chords
//  spec in Implementation Decisions): maj, min, 7, maj7, min7, dim, aug, sus2,
//  sus4, add9, 6, 6/9, 9, 11, 13, 7♭9, 7♯9, m7♭5, dim7, and friends.
//
//  A note on extended chords (9, 11, 13): in theory a full 13th chord stacks
//  seven notes, but in practice (and on a six-string guitar) certain tones are
//  omitted by convention. We encode the *commonly voiced* note set for each so
//  the Chords tool gets practical, playable spellings — and we document each
//  omission so it's a deliberate, testable choice rather than an accident.
//

import Foundation

/// Semitone offsets from the root for the most useful chord intervals, named for
/// readability so the recipes below read like the music-theory shorthand a
/// guitarist already knows. (These are *chromatic* semitone counts from the
/// root, not scale degrees.)
private enum ChordInterval {
    static let root = 0
    static let minorSecond = 1
    static let majorSecond = 2      // also the "9th" when an octave up; same PC
    static let minorThird = 3
    static let majorThird = 4
    static let perfectFourth = 5    // the "11th" one octave up; same PC
    static let diminishedFifth = 6  // ♭5 / tritone
    static let perfectFifth = 7
    static let augmentedFifth = 8   // ♯5
    static let majorSixth = 9       // also the "13th"; same PC
    static let minorSeventh = 10
    static let majorSeventh = 11
    static let minorNinth = 13      // ♭9 — kept as 13 (not 1) to mark register
    static let majorNinth = 14      // 9
    static let augmentedNinth = 15  // ♯9
    static let perfectEleventh = 17 // 11
    static let majorThirteenth = 21 // 13
}

/// The catalogue of chord qualities. `CaseIterable` lets tests iterate every
/// quality, and the UI build the quality picker, without anyone maintaining a
/// separate list.
public enum ChordQuality: CaseIterable, Hashable, Sendable {
    // Triads
    case major          // 1 3 5
    case minor          // 1 ♭3 5
    case diminished     // 1 ♭3 ♭5
    case augmented      // 1 3 ♯5
    case sus2           // 1 2 5   (third replaced by a 2nd)
    case sus4           // 1 4 5   (third replaced by a 4th)

    // Added-note & sixth chords
    case add9           // 1 3 5 9      (a triad + the 9th, NO 7th)
    case sixth          // 1 3 5 6      ("6" chord)
    case minorSixth     // 1 ♭3 5 6     ("m6")
    case sixNine        // 1 3 5 6 9    ("6/9")

    // Sevenths
    case dominantSeventh    // 1 3 5 ♭7   ("7")
    case majorSeventh       // 1 3 5 7    ("maj7")
    case minorSeventh       // 1 ♭3 5 ♭7  ("m7")
    case minorMajorSeventh  // 1 ♭3 5 7   ("mMaj7")
    case halfDiminished     // 1 ♭3 ♭5 ♭7 ("m7♭5" / ø7)
    case diminishedSeventh  // 1 ♭3 ♭5 ♭♭7 ("dim7" — the ♭♭7 sounds as a 6th)
    case augmentedSeventh   // 1 3 ♯5 ♭7  ("7♯5" / aug7)

    // Extended dominants (9 / 11 / 13). See note at top re: omitted tones.
    case dominantNinth      // 1 3 (5) ♭7 9
    case dominantEleventh   // 1 (3) 5 ♭7 9 11   (3rd usually omitted)
    case dominantThirteenth // 1 3 (5) ♭7 9 (11) 13
    case majorNinth         // 1 3 5 7 9
    case minorNinth         // 1 ♭3 5 ♭7 9

    // Altered dominants
    case dominantSeventhFlatNine   // 1 3 5 ♭7 ♭9   ("7♭9")
    case dominantSeventhSharpNine  // 1 3 5 ♭7 ♯9   ("7♯9", the "Hendrix chord")

    /// The recipe: semitone offsets from the root, ascending. The root (0) is
    /// always first. Offsets above 11 deliberately exceed one octave so that, in
    /// a future voicing engine, a 9th can sit above the 7th rather than colliding
    /// with the 2nd — but for *pitch-class* membership (this module's job) they
    /// still reduce to the right note via the octave wrap in `Chord.notes`.
    public var semitoneOffsets: [Int] {
        switch self {
        // Triads
        case .major:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth]
        case .minor:
            return [ChordInterval.root, ChordInterval.minorThird, ChordInterval.perfectFifth]
        case .diminished:
            return [ChordInterval.root, ChordInterval.minorThird, ChordInterval.diminishedFifth]
        case .augmented:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.augmentedFifth]
        case .sus2:
            return [ChordInterval.root, ChordInterval.majorSecond, ChordInterval.perfectFifth]
        case .sus4:
            return [ChordInterval.root, ChordInterval.perfectFourth, ChordInterval.perfectFifth]

        // Added-note & sixths
        case .add9:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.majorNinth]
        case .sixth:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.majorSixth]
        case .minorSixth:
            return [ChordInterval.root, ChordInterval.minorThird, ChordInterval.perfectFifth,
                    ChordInterval.majorSixth]
        case .sixNine:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.majorSixth, ChordInterval.majorNinth]

        // Sevenths
        case .dominantSeventh:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.minorSeventh]
        case .majorSeventh:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.majorSeventh]
        case .minorSeventh:
            return [ChordInterval.root, ChordInterval.minorThird, ChordInterval.perfectFifth,
                    ChordInterval.minorSeventh]
        case .minorMajorSeventh:
            return [ChordInterval.root, ChordInterval.minorThird, ChordInterval.perfectFifth,
                    ChordInterval.majorSeventh]
        case .halfDiminished:
            return [ChordInterval.root, ChordInterval.minorThird, ChordInterval.diminishedFifth,
                    ChordInterval.minorSeventh]
        case .diminishedSeventh:
            // The diminished 7th interval is enharmonically a major 6th (9
            // semitones): a fully-diminished chord stacks three minor thirds.
            return [ChordInterval.root, ChordInterval.minorThird, ChordInterval.diminishedFifth,
                    ChordInterval.majorSixth]
        case .augmentedSeventh:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.augmentedFifth,
                    ChordInterval.minorSeventh]

        // Extended dominants & majors/minors
        case .dominantNinth:
            // Fifth retained here (it's only *optionally* dropped when voicing).
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.minorSeventh, ChordInterval.majorNinth]
        case .dominantEleventh:
            // 3rd omitted by convention (it clashes a half-step with the 11th);
            // result: root, 5, ♭7, 9, 11.
            return [ChordInterval.root, ChordInterval.perfectFifth, ChordInterval.minorSeventh,
                    ChordInterval.majorNinth, ChordInterval.perfectEleventh]
        case .dominantThirteenth:
            // 11th omitted by convention; the 5th is kept here for completeness.
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.minorSeventh, ChordInterval.majorNinth,
                    ChordInterval.majorThirteenth]
        case .majorNinth:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.majorSeventh, ChordInterval.majorNinth]
        case .minorNinth:
            return [ChordInterval.root, ChordInterval.minorThird, ChordInterval.perfectFifth,
                    ChordInterval.minorSeventh, ChordInterval.majorNinth]

        // Altered dominants
        case .dominantSeventhFlatNine:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.minorSeventh, ChordInterval.minorNinth]
        case .dominantSeventhSharpNine:
            return [ChordInterval.root, ChordInterval.majorThird, ChordInterval.perfectFifth,
                    ChordInterval.minorSeventh, ChordInterval.augmentedNinth]
        }
    }

    /// A short symbol suitable for labelling, using the conventional shorthand
    /// (e.g. "maj7", "m7♭5", "7♯9"). The root letter is prepended by `Chord`.
    public var symbol: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        case .diminished: return "dim"
        case .augmented: return "aug"
        case .sus2: return "sus2"
        case .sus4: return "sus4"
        case .add9: return "add9"
        case .sixth: return "6"
        case .minorSixth: return "m6"
        case .sixNine: return "6/9"
        case .dominantSeventh: return "7"
        case .majorSeventh: return "maj7"
        case .minorSeventh: return "m7"
        case .minorMajorSeventh: return "mMaj7"
        case .halfDiminished: return "m7♭5"
        case .diminishedSeventh: return "dim7"
        case .augmentedSeventh: return "7♯5"
        case .dominantNinth: return "9"
        case .dominantEleventh: return "11"
        case .dominantThirteenth: return "13"
        case .majorNinth: return "maj9"
        case .minorNinth: return "m9"
        case .dominantSeventhFlatNine: return "7♭9"
        case .dominantSeventhSharpNine: return "7♯9"
        }
    }
}
