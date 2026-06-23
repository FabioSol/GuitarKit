//
//  Temperament.swift
//  GuitarKit
//
//  A "temperament" is a system that decides exactly how in-tune each note
//  should be, expressed as a tiny fractional adjustment (in cents) away from
//  the mathematically-pure equal-temperament pitch.
//
//  Pure logic only — no UI, no audio.
//

import Foundation

// MARK: - Temperament protocol

/// Supplies a per-string tuning offset, measured in **cents**.
///
/// WHAT IS A CENT?
/// A cent is 1/100th of a semitone, so there are 1200 cents in an octave. It's
/// the standard fine-grained unit for "how sharp/flat" a pitch is. A guitar
/// "sweetened" tuning nudges certain strings by a few cents (e.g. the G string
/// a couple cents flat) so chords sound in tune to the ear rather than only on
/// paper.
///
/// WHY A PROTOCOL?
/// A `protocol` is Swift's way of describing a *capability* ("anything that can
/// tell me a string's cent offset") without saying *how* it's implemented. This
/// is the classic seam for swappable strategies: the rest of the app depends on
/// the abstract `Temperament`, and we can drop in `EqualTemperament` today or a
/// `Sweetened` profile later (PRD: sweetened is in the model, UI hidden under
/// Advanced) without changing a single caller.
///
/// `Sendable` requires conformers to be safe across concurrency boundaries,
/// which our value-type implementations are.
public protocol Temperament: Sendable {
    /// A short identifier for display/persistence (e.g. "Equal").
    var name: String { get }

    /// The cent offset to apply to the string at `stringIndex`.
    ///
    /// `stringIndex` is 0-based and refers to a string's position within a
    /// tuning's `strings` array. The total string count is passed too, because
    /// some sweetened profiles are defined relative to the instrument layout
    /// (e.g. "the high E of a 6-string"). Equal temperament ignores both and
    /// always returns 0.
    ///
    /// `-> Double`: cents are fractional, so we return a floating-point value.
    func centOffset(forStringIndex stringIndex: Int, stringCount: Int) -> Double
}

// MARK: - EqualTemperament

/// The standard 12-tone equal temperament: every semitone is an identical
/// frequency ratio and there are *no* per-string sweetening offsets.
///
/// This is the v1 default. Because it returns 0 for every string, frequency
/// derivation through it is exactly the textbook `referenceA · 2^((midi-69)/12)`.
///
/// `struct` (value type) with no stored properties — it's effectively a
/// stateless strategy object.
public struct EqualTemperament: Temperament {
    public let name = "Equal"

    /// Public, parameter-less init so other modules can create one.
    public init() {}

    /// Always 0 — equal temperament applies no sweetening. The underscores on
    /// the parameter names (`_ stringIndex`) mean callers don't write argument
    /// labels, and we ignore the values entirely here.
    public func centOffset(forStringIndex _: Int, stringCount _: Int) -> Double {
        0
    }
}

// MARK: - SweetenedTemperament

/// A temperament defined by an explicit table of per-string cent offsets.
///
/// This proves the *model* supports sweetened tuning (an acceptance criterion)
/// even though the UI to choose it stays hidden under Advanced for v1. A typical
/// 6-string acoustic "sweetened" profile might nudge the B and G strings a few
/// cents to tame the major-third beating in open chords.
///
/// We store the offsets in an array indexed by string position. If a caller asks
/// for a string outside the table (e.g. a 7-string instrument using a 6-entry
/// profile), we safely return 0 rather than crashing — sweetening simply doesn't
/// apply to strings the profile doesn't describe.
public struct SweetenedTemperament: Temperament {
    public let name: String

    /// One cent value per string, in string order. `private let` keeps the raw
    /// storage an implementation detail; callers go through `centOffset`.
    private let offsets: [Double]

    /// - Parameters:
    ///   - name: label for display/persistence.
    ///   - offsets: cents per string, index 0 = first string in the tuning.
    public init(name: String = "Sweetened", offsets: [Double]) {
        self.name = name
        self.offsets = offsets
    }

    public func centOffset(forStringIndex stringIndex: Int, stringCount _: Int) -> Double {
        // `indices.contains` is a bounds-safe check: it returns false for any
        // index outside 0..<offsets.count, so we never index out of range.
        guard offsets.indices.contains(stringIndex) else { return 0 }
        return offsets[stringIndex]
    }
}
