//
//  Key.swift
//  GuitarKit — Harmony domain
//
//  A *key* is a tonal centre plus a mode (major or minor): "C major", "A minor",
//  "F# major", etc. From a key we want three things the Circle-of-Fifths tool
//  needs (PRD story 44): its key *signature* (which notes are sharp/flat), its
//  *relative minor* (or major), and its *seven diatonic triads* (built in
//  DiatonicTriads.swift).
//
//  The cleanest way to derive a key signature is the circle of fifths itself, so
//  this file models keys by their position on that circle. That single integer
//  ("how many sharps/flats") drives everything: the signature, the tonic's
//  spelling, and adjacency around the circle (CircleOfFifths.swift).
//

import Foundation

/// Major or minor. (v1's harmony layer only needs these two "modes" at the *key*
/// level; the seven church modes live in Scale.swift, which is a different,
/// scale-shape concept.)
public enum KeyMode: Hashable, Sendable {
    case major
    case minor
}

/// A musical key: a tonic note (spelled) + a mode.
///
/// We expose two ways to build one:
///  • directly from a tonic `SpelledNote` + mode (e.g. for ad-hoc use), and
///  • from a *circle-of-fifths position* (the canonical path that knows the
///    "official" enharmonic spelling — e.g. position +6 major is F# major, not
///    Gb major).
public struct Key: Hashable, Sendable {
    public let tonic: SpelledNote
    public let mode: KeyMode

    public init(tonic: SpelledNote, mode: KeyMode) {
        self.tonic = tonic
        self.mode = mode
    }

    // MARK: - Circle-of-fifths construction

    /// The order in which sharps are *added* to a key signature as you move
    /// clockwise (sharpwards) around the circle: F, C, G, D, A, E, B. This is
    /// the famous "Father Charles Goes Down And Ends Battle" mnemonic. The
    /// first sharp key (G major) sharpens F, the next (D major) adds C, etc.
    private static let sharpOrder: [Letter] = [.f, .c, .g, .d, .a, .e, .b]

    /// Flats are added in the exact reverse order: B, E, A, D, G, C, F
    /// ("Battle Ends And Down Goes Charles' Father"). F major (one flat)
    /// flattens B, Bb major adds E, etc.
    private static let flatOrder: [Letter] = [.b, .e, .a, .d, .g, .c, .f]

    /// Build the *major* key at a given circle-of-fifths position, where:
    ///   0  = C major (no sharps/flats)
    ///  +n  = n positions clockwise  → n sharps   (G, D, A, E, B, F#, C#)
    ///  -n  = n positions anticlockwise → n flats (F, Bb, Eb, Ab, Db, Gb, Cb)
    ///
    /// We support the full ±7 range so all standard signatures (including the
    /// enharmonic extremes C# major / Cb major) are expressible.
    ///
    /// How the tonic is derived: moving one step clockwise on the circle goes up
    /// a perfect fifth (7 semitones); anticlockwise goes down a fifth. We start
    /// at C and apply that, then figure out the correct *letter* so the spelling
    /// is the conventional one (sharps spelled with sharps, flats with flats).
    public static func major(circlePosition: Int) -> Key {
        Key(tonic: majorTonic(circlePosition: circlePosition), mode: .major)
    }

    /// The natural-minor key sharing a given major key's signature lives three
    /// circle positions to the *flat* side in major-terms, but it is far simpler
    /// to define a minor key directly by *its own* signature position. A minor
    /// key at circle position `p` has the same signature as the major key at the
    /// same `p` (that is the definition of relative keys), but its tonic is the
    /// relative minor of that major. Example: position 0 → A minor (relative of
    /// C major); position +1 → E minor (relative of G major).
    public static func minor(circlePosition: Int) -> Key {
        let relativeMajorTonic = majorTonic(circlePosition: circlePosition)
        // The relative minor tonic is a minor third (3 semitones) below the
        // major tonic, and — crucially for spelling — two *letters* below
        // (e.g. C major → A minor: C down to A is two letter-steps).
        let minorLetter = relativeMajorTonic.letter.advanced(by: -2)
        let minorTonic = spell(pitchClass: relativeMajorTonic.pitchClass.transposed(by: -3),
                               as: minorLetter)
        return Key(tonic: minorTonic, mode: .minor)
    }

    /// Shared helper: the tonic `SpelledNote` of the major key at a position.
    private static func majorTonic(circlePosition: Int) -> SpelledNote {
        // Clamp/normalise is intentionally NOT done: callers stay within ±7.
        // Pitch class: C is 0; each clockwise step is +7 semitones (a fifth).
        let pc = PitchClass.c.transposed(by: 7 * circlePosition)
        // Letter: each clockwise step also advances the letter by 4 (C→G→D→A…
        // is +4 letters each time, wrapping). Anticlockwise advances by -4
        // (equivalently +3), giving C→F→Bb→Eb… Picking the letter this way (not
        // by pitch class) is what guarantees correct sharp-vs-flat spelling.
        let letter = Letter.c.advanced(by: 4 * circlePosition)
        return spell(pitchClass: pc, as: letter)
    }

    /// Given a target pitch class and the *letter* we want to spell it with,
    /// compute the accidental that makes them agree, choosing the smallest
    /// magnitude (so we get a single sharp/flat rather than, say, a wild
    /// double-flat). This is pure arithmetic: how far is the pitch class from
    /// the letter's natural, measured as a signed offset in -6...+5 then nudged
    /// into the "nearest" -2...+2-ish range that music actually uses.
    private static func spell(pitchClass target: PitchClass, as letter: Letter) -> SpelledNote {
        let natural = letter.naturalPitchClass.rawValue
        // Raw difference in 0...11.
        var diff = (target.rawValue - natural + 12) % 12
        // Map 7...11 to the negative side (-5...-1) so e.g. "11 semitones up"
        // reads as "1 down" — i.e. prefer Cb over B###### nonsense.
        if diff > 6 { diff -= 12 }
        return SpelledNote(letter: letter, accidental: diff)
    }

    // MARK: - Key signature

    /// The set of altered notes in this key's signature, as spelled notes.
    /// For C major / A minor this is empty. For G major it is `[F♯]`; for F
    /// major it is `[B♭]`; and so on. Order follows the conventional
    /// sharp/flat order so the result reads the way it appears on a staff.
    ///
    /// We compute it from the *signature position* — for a major key that is its
    /// own circle position; for a minor key it is the position of its relative
    /// major (which, by construction above, is the same number we'd pass to
    /// `Key.minor(circlePosition:)`). We recover that number from the tonic.
    public var keySignature: [SpelledNote] {
        let position = signaturePosition
        if position > 0 {
            // `position` sharps, taken from the front of the sharp order.
            return Self.sharpOrder.prefix(position).map { SpelledNote(letter: $0, accidental: +1) }
        } else if position < 0 {
            // `-position` flats, taken from the front of the flat order.
            return Self.flatOrder.prefix(-position).map { SpelledNote(letter: $0, accidental: -1) }
        } else {
            return []  // C major / A minor: no accidentals.
        }
    }

    /// Convenience counts so the UI/tests can ask "how many sharps?" directly.
    /// A positive number means sharps, negative means flats, zero means natural.
    public var sharpsOrFlats: Int { signaturePosition }

    /// Recover the circle-of-fifths *signature* position from the tonic spelling.
    /// We rebuild the major→position map by walking positions -7...+7; the
    /// matching tonic (for a major key) or relative-major tonic (for a minor
    /// key) tells us the signature. Doing it by lookup keeps the spelling and
    /// the position guaranteed-consistent with the constructors above.
    private var signaturePosition: Int {
        // The note whose major key defines our signature:
        // - for a major key, that's our own tonic;
        // - for a minor key, it's our relative major (a minor third *above*).
        let majorTonicPC: PitchClass = (mode == .major)
            ? tonic.pitchClass
            : tonic.pitchClass.transposed(by: +3)
        let majorTonicLetter: Letter = (mode == .major)
            ? tonic.letter
            : tonic.letter.advanced(by: +2)

        // First try to match on BOTH pitch class and letter (the precise,
        // spelling-aware path) — this distinguishes e.g. F♯ major (+6) from
        // G♭ major (-6), which sound identical but have different signatures.
        for position in -7...7 {
            let candidate = Self.majorTonic(circlePosition: position)
            if candidate.pitchClass == majorTonicPC && candidate.letter == majorTonicLetter {
                return position
            }
        }
        // Fallback for hand-built/unusual spellings: match by pitch class alone,
        // preferring the position closest to C (smallest |position|, so we pick
        // the simpler signature when two enharmonic ones exist).
        let byPitchClass = (-7...7)
            .filter { Self.majorTonic(circlePosition: $0).pitchClass == majorTonicPC }
            .min(by: { abs($0) < abs($1) })
        return byPitchClass ?? 0
    }

    // MARK: - Relative & parallel keys

    /// The relative key: the major↔minor pair that *shares this key's signature*.
    /// C major ↔ A minor, G major ↔ E minor, etc. This is PRD story 44's
    /// "relative minor" (and its inverse for minor keys).
    public var relative: Key {
        switch mode {
        case .major:
            // Relative minor: tonic a minor third (3 semitones) down, two
            // letters down (C→A, G→E, F→D…).
            let letter = tonic.letter.advanced(by: -2)
            let pc = tonic.pitchClass.transposed(by: -3)
            return Key(tonic: Self.spell(pitchClass: pc, as: letter), mode: .minor)
        case .minor:
            // Relative major: tonic a minor third up, two letters up
            // (A→C, E→G, D→F…).
            let letter = tonic.letter.advanced(by: +2)
            let pc = tonic.pitchClass.transposed(by: +3)
            return Key(tonic: Self.spell(pitchClass: pc, as: letter), mode: .major)
        }
    }

    /// The *parallel* key: same tonic, opposite mode (C major ↔ C minor). Not the
    /// same as the relative key — included because it's a common theory concept
    /// and trivial to provide.
    public var parallel: Key {
        Key(tonic: tonic, mode: mode == .major ? .minor : .major)
    }

    /// A display name like "C major", "F♯ major", "A minor".
    public var name: String {
        "\(tonic.name) \(mode == .major ? "major" : "minor")"
    }
}
