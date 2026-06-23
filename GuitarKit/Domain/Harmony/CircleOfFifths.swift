//
//  CircleOfFifths.swift
//  GuitarKit — Harmony domain
//
//  The circle of fifths is the ring of all twelve major keys arranged so that
//  each step clockwise goes up a perfect fifth: C → G → D → A → E → B → F♯ →
//  D♭ → A♭ → E♭ → B♭ → F → (back to C). Neighbours on the circle differ by only
//  one sharp/flat, which is *why* the tool exists: adjacent keys sound closely
//  related. This file gives the Circle-of-Fifths tool (PRD stories 44–49) the
//  pure "who is next to whom" relationships.
//

import Foundation

/// Namespacing the circle as an `enum` with only static members is a common
/// Swift idiom for "a bag of related functions with no instances." Unlike a
/// `struct`, an `enum` with no cases *cannot be instantiated at all*, which
/// documents the intent: there is only ever one conceptual circle of fifths.
public enum CircleOfFifths {

    /// The twelve circle positions we expose, clockwise from C, using the
    /// conventional spelling at each seat (sharps on the right half, flats on
    /// the left, meeting at the enharmonic bottom F♯/G♭). We choose F♯ (+6) over
    /// G♭ (-6) for the single bottom seat; both are provided as keys elsewhere
    /// if needed, but the canonical wheel has twelve seats.
    ///
    /// Positions: 0=C, 1=G, 2=D, 3=A, 4=E, 5=B, 6=F♯,
    ///            then the flat side as negative-equivalent seats
    ///            7=D♭(-5), 8=A♭(-4), 9=E♭(-3), 10=B♭(-2), 11=F(-1).
    private static let majorPositions: [Int] = [0, 1, 2, 3, 4, 5, 6, -5, -4, -3, -2, -1]

    /// The twelve major keys in clockwise order starting from C major.
    /// Computed once (a `static let` is initialised lazily and exactly once),
    /// so callers can index into a stable, ordered ring.
    public static let majorKeys: [Key] = majorPositions.map { Key.major(circlePosition: $0) }

    /// The twelve relative-minor keys, in the *same* clockwise order, so that
    /// `minorKeys[i]` is the relative minor of `majorKeys[i]` — exactly how the
    /// inner ring of a circle-of-fifths diagram lines up (A minor sits inside
    /// C major, E minor inside G major, ...).
    public static let minorKeys: [Key] = majorKeys.map { $0.relative }

    /// The number of seats on the circle (twelve, naturally). Kept as a named
    /// constant so the wrap-around maths below reads clearly.
    public static let count = 12

    /// The major key `steps` positions clockwise from a given key (negative
    /// `steps` goes anticlockwise). Wraps around the ring, so going clockwise
    /// from F lands back on C. This is the core "adjacency" primitive: the key
    /// immediately clockwise is `clockwise(from: key, steps: 1)`.
    ///
    /// We work in *signature-position* space (each step is one sharp/flat), then
    /// rebuild the key — this keeps spellings canonical and avoids any drift.
    public static func clockwise(from key: Key, steps: Int = 1) -> Key {
        let index = majorIndex(of: key)
        // Add steps and wrap into 0..<count. The double-modulo keeps the result
        // non-negative even when `steps` is negative (see PitchClass for the
        // same trick and why Swift's % alone isn't enough).
        let wrapped = ((index + steps) % count + count) % count
        let resultMajor = majorKeys[wrapped]
        // Preserve the caller's mode: if they asked about a minor key, return
        // the minor key at the destination seat (its relative minor).
        return key.mode == .major ? resultMajor : resultMajor.relative
    }

    /// Convenience: the key one seat clockwise (up a fifth) — its closest
    /// "sharper" neighbour.
    public static func next(_ key: Key) -> Key { clockwise(from: key, steps: 1) }

    /// Convenience: the key one seat anticlockwise (down a fifth / up a fourth)
    /// — its closest "flatter" neighbour.
    public static func previous(_ key: Key) -> Key { clockwise(from: key, steps: -1) }

    /// The two immediate neighbours of a key on the circle, as
    /// `(flatward, sharpward)`. Handy for the wheel UI that highlights the keys
    /// either side of the current selection.
    public static func neighbors(of key: Key) -> (previous: Key, next: Key) {
        (previous(key), next(key))
    }

    /// How many circle steps apart two keys are, by the *shortest* path around
    /// the ring (always 0...6). Two adjacent keys → 1; opposite keys (a tritone
    /// apart, the "furthest" relationship) → 6. Useful as a similarity metric.
    public static func distance(from a: Key, to b: Key) -> Int {
        let raw = abs(majorIndex(of: a) - majorIndex(of: b))
        // The ring is circular, so the real distance is the smaller of going one
        // way (`raw`) or the other (`count - raw`).
        return min(raw, count - raw)
    }

    /// Find a key's seat index (0..<12) on the major ring, comparing by the
    /// *sounding* tonic (pitch class) so a minor key maps to its relative-major
    /// seat and enharmonic spellings still resolve. Falls back to 0 (C) if a
    /// truly unknown key is passed, which can't happen for keys produced by this
    /// module's constructors.
    private static func majorIndex(of key: Key) -> Int {
        // The pitch class of the major key that owns this seat: for a major key
        // it's the tonic; for a minor key it's the relative major (a minor third
        // up — A minor's seat is C's).
        let seatPC = key.mode == .major
            ? key.tonic.pitchClass
            : key.tonic.pitchClass.transposed(by: +3)
        return majorKeys.firstIndex { $0.tonic.pitchClass == seatPC } ?? 0
    }
}
