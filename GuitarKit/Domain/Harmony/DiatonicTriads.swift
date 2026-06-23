//
//  DiatonicTriads.swift
//  GuitarKit — Harmony domain
//
//  Every major or minor key has seven *diatonic triads* — the chords you get by
//  stacking thirds on each note of its scale, using only notes from that scale.
//  In a major key they come out as the famous pattern:
//
//      I   ii   iii   IV   V   vi   vii°
//    major min  min  major major min diminished
//
//  These power the Circle-of-Fifths tool's "diatonic chord chips" (PRD story 44/
//  46) and give the Chords tool a key-aware suggestion set.
//
//  We derive them *from the scale* rather than hard-coding, so the relationship
//  is provably correct and works for the minor key too (which yields
//  i ii° ♭III iv v ♭VI ♭VII for natural minor).
//

import Foundation

/// A diatonic chord together with the scale-degree info that gives it meaning
/// in the key: which degree (1...7) it's built on, and a Roman-numeral label
/// (uppercase for major, lowercase for minor, with ° for diminished).
public struct DiatonicChord: Hashable, Sendable {
    /// 1-based scale degree this chord is built on (1 = the tonic triad, etc.).
    public let degree: Int
    /// The Roman-numeral label, e.g. "I", "ii", "V", "vii°".
    public let romanNumeral: String
    /// The actual chord (root pitch class + quality).
    public let chord: Chord
}

/// A small functions-only namespace (see CircleOfFifths for the same idiom) that
/// computes the diatonic triads of a key.
public enum DiatonicTriads {

    /// The seven diatonic triads of `key`, in scale order (degree 1 → 7).
    ///
    /// Algorithm — "stack thirds within the scale":
    ///  1. Take the key's scale as a 7-note set of pitch classes.
    ///  2. For each degree `i`, the triad is the notes at scale positions
    ///     `i`, `i+2`, `i+4` (the root, the third *up the scale*, and the fifth
    ///     *up the scale*), wrapping around the octave. "Thirds" here means
    ///     "skip a scale note", which is why we step by 2 indices.
    ///  3. Measure the actual semitone gaps between those three notes to decide
    ///     the quality (major / minor / diminished / augmented), because the
    ///     scale's uneven spacing makes some triads major and others minor.
    public static func triads(in key: Key) -> [DiatonicChord] {
        // Choose the scale that defines the key. Major keys use the major scale;
        // minor keys use *natural* minor for the standard diatonic set. (The
        // harmonic/melodic variants change a couple of chords; v1's chip set
        // uses the natural-minor triads, the most common teaching default.)
        let scaleType: ScaleType = (key.mode == .major) ? .major : .naturalMinor
        let scale = Scale(root: key.tonic.pitchClass, type: scaleType)
        let degrees = scale.notes   // 7 pitch classes, index 0 == degree 1

        // Roman-numeral *base* numerals by degree (always 1..7 → I..VII); case
        // and the ° suffix are applied per-quality below.
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

        var result: [DiatonicChord] = []
        for i in 0..<degrees.count {
            let rootPC = degrees[i]
            let thirdPC = degrees[(i + 2) % degrees.count]
            let fifthPC = degrees[(i + 4) % degrees.count]

            // Semitone gaps that classify the triad. We measure the third above
            // the root and the fifth above the root, always as upward distances
            // (0...11), so the modulo wrap is handled for triads that straddle
            // the octave.
            let thirdInterval = thirdPC.semitoneDistance(from: rootPC) // 3=min, 4=maj
            let fifthInterval = fifthPC.semitoneDistance(from: rootPC) // 6=dim,7=perf,8=aug

            let quality = classifyTriad(third: thirdInterval, fifth: fifthInterval)

            // Roman numeral: uppercase for major/augmented, lowercase for
            // minor/diminished, with a trailing ° for diminished (and + for
            // augmented, which can appear in harmonic-minor-derived sets).
            let baseNumeral = numerals[i]
            let roman: String
            switch quality {
            case .major:        roman = baseNumeral
            case .augmented:    roman = baseNumeral + "+"
            case .minor:        roman = baseNumeral.lowercased()
            case .diminished:   roman = baseNumeral.lowercased() + "°"
            default:            roman = baseNumeral // unreachable for triads
            }

            result.append(DiatonicChord(degree: i + 1,
                                        romanNumeral: roman,
                                        chord: Chord(root: rootPC, quality: quality)))
        }
        return result
    }

    /// Map the two measured intervals onto a triad quality. This is just the
    /// definition of the four triad types in terms of their third and fifth:
    ///   minor 3rd (3) + dim 5th (6)  → diminished
    ///   minor 3rd (3) + perfect 5th  → minor
    ///   major 3rd (4) + perfect 5th  → major
    ///   major 3rd (4) + aug 5th (8)  → augmented
    private static func classifyTriad(third: Int, fifth: Int) -> ChordQuality {
        switch (third, fifth) {
        case (3, 6): return .diminished
        case (3, 7): return .minor
        case (4, 7): return .major
        case (4, 8): return .augmented
        // Any other combination shouldn't arise from a diatonic major/natural-
        // minor scale; default to major so the function stays total. (If we ever
        // feed harmonic minor here, the augmented and diminished cases above
        // already cover its extra colours.)
        default: return .major
        }
    }
}
