//
//  CustomTuningSupport.swift
//  GuitarKit
//
//  Pure, deterministic helpers that back the custom-tuning editor (slice #12,
//  PRD stories 26–32). Two jobs live here:
//    1. `autoSuggestedName(for:)` — turn a set of open-string notes into a
//       sensible default name (e.g. EADGBE → "EADGBE", DADGAD → "DADGAD") so the
//       player can save in one tap (story 31).
//    2. `outOfRangeStringIndices(...)` / `isOutOfRange(...)` — a *gentle*,
//       non-blocking check for strings nudged wildly away from the instrument's
//       home tuning, so the editor can show a soft warning banner without ever
//       refusing the save (acceptance criterion: "warn without blocking").
//
//  WHY A SEPARATE PURE FILE (no SwiftUI here)?
//  Like the rest of `Domain/`, this file imports only Foundation. Keeping the
//  naming + range logic free of UI is exactly what lets us unit-test it in
//  isolation (see CustomTuningTests) — the editor view then just *calls* these
//  and renders the result. This mirrors how `PitchCalculator` and
//  `InstrumentLibrary` keep their logic UI-free.
//

import Foundation

// MARK: - CustomTuningSupport

/// A namespace (empty `enum`, so it can never be instantiated) gathering the
/// pure helpers the custom-tuning editor relies on. Same "bag of statics"
/// pattern as `InstrumentLibrary` / `GKColor`: callers write
/// `CustomTuningSupport.autoSuggestedName(for: strings)`.
public enum CustomTuningSupport {

    // MARK: Auto-suggested name

    /// Build a sensible default tuning name from a set of open-string notes,
    /// low → high — the spelling a guitarist would actually say out loud.
    ///
    /// THE RULE:
    /// We concatenate each string's pitch-class *letter* (ignoring the octave),
    /// low string first. So standard guitar (E A D G B E) becomes "EADGBE" and
    /// the Celtic staple (D A D G A D) becomes "DADGAD" — exactly the names
    /// players already use. Sharps keep their "#" (so a string on F# reads
    /// "F#"), which is why we reuse `PitchClass.name` rather than hand-rolling a
    /// letter table.
    ///
    /// EDGE CASE: an empty string set (a brand-new blank tuning before any note
    /// is set — though the editor always seeds at least the right *count*)
    /// falls back to a plain "Custom" so we never produce an empty name.
    ///
    /// - Parameter strings: the open-string notes, low → high.
    /// - Returns: a concatenated-letters name, or "Custom" when there are no
    ///   strings to spell.
    public static func autoSuggestedName(for strings: [Note]) -> String {
        // No notes → no spelling to build; hand back a safe placeholder.
        guard !strings.isEmpty else { return "Custom" }

        // `map` turns each Note into its pitch-class name ("E", "A", "F#"…),
        // then `joined()` glues them into one string with no separator. We drop
        // the octave deliberately: tuning names are about the letters, not which
        // octave each sits in.
        return strings
            .map { $0.pitchClass.name }
            .joined()
    }

    // MARK: Out-of-range warning

    /// How far (in semitones) a string may sit from its home-tuning counterpart
    /// before we flag it. A whole *octave* (12 semitones) is the threshold: a
    /// few semitones of nudging is normal and musical (drop tunings, half-step
    /// down, open tunings all stay well within an octave of standard), but a
    /// string pushed more than an octave away is almost certainly a slip, a
    /// physically implausible target, or a mistake worth a gentle heads-up.
    ///
    /// `public` so the editor (and tests) can show the exact number in copy if
    /// they want, and so the rule is documented in one obvious place.
    public static let outOfRangeThresholdSemitones = 12

    /// The indices of strings (0-based, low → high) that sit MORE than
    /// `outOfRangeThresholdSemitones` away from the instrument's home tuning —
    /// the strings the editor should flag in its gentle, non-blocking warning.
    ///
    /// HOW THE COMPARISON WORKS:
    /// We compare each edited string against the SAME-INDEX string of the
    /// instrument's default (home) tuning, by MIDI number, so the distance is a
    /// plain semitone count. A string is "out of range" only if its absolute
    /// distance exceeds the threshold (strictly `>`, so a string sitting exactly
    /// an octave away is still considered fine).
    ///
    /// DEFENSIVE EDGES (so this can never crash and never false-alarms):
    ///   • If the instrument has no home tuning (never happens in the shipped
    ///     library, but we guard it), we have nothing to compare against, so we
    ///     report no out-of-range strings.
    ///   • We only compare positions that exist in BOTH lists. If the edited set
    ///     somehow has more strings than the home tuning (it shouldn't — the
    ///     editor fixes the count to the instrument), the extra strings are left
    ///     unjudged rather than blamed against a missing reference.
    ///
    /// - Parameters:
    ///   - strings: the edited open-string notes, low → high.
    ///   - instrument: the instrument being tuned (supplies the home reference).
    /// - Returns: the indices of out-of-range strings (empty when all are fine).
    public static func outOfRangeStringIndices(
        strings: [Note],
        for instrument: Instrument
    ) -> [Int] {
        // Nothing to compare against → nothing to flag. `home.strings` is the
        // per-string reference we measure distance from.
        guard let home = instrument.defaultTuning else { return [] }

        var flagged: [Int] = []

        // Walk each edited string by index. We only look at indices that also
        // exist in the home tuning so the lookup `home.strings[index]` is always
        // safe (no out-of-bounds), and an unmatched extra string is skipped.
        for index in strings.indices where index < home.strings.count {
            let edited = strings[index]
            let reference = home.strings[index]

            // Distance in semitones is just the gap between MIDI numbers; `abs`
            // makes it direction-agnostic (too high OR too low both count).
            let distance = abs(edited.midiNumber - reference.midiNumber)

            if distance > outOfRangeThresholdSemitones {
                flagged.append(index)
            }
        }

        return flagged
    }

    /// A convenience yes/no wrapper over `outOfRangeStringIndices` for the
    /// editor's "should I show the warning banner at all?" check. `true` when at
    /// least one string is out of range.
    ///
    /// - Parameters:
    ///   - strings: the edited open-string notes, low → high.
    ///   - instrument: the instrument being tuned.
    public static func isOutOfRange(
        strings: [Note],
        for instrument: Instrument
    ) -> Bool {
        !outOfRangeStringIndices(strings: strings, for: instrument).isEmpty
    }
}
