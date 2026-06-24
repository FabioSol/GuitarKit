//
//  StandardChordLibrary.swift
//  GuitarKit — Harmony domain
//
//  A small, HAND-AUTHORED dictionary of the classic open-position chord shapes
//  for STANDARD guitar tuning (EADGBE). These are the first chords every
//  guitarist learns — the "cowboy chords" — and they're the gold standard for a
//  beginner app: instantly recognizable, easy to finger, and unambiguously
//  correct.
//
//  WHY A CURATED LIBRARY ALONGSIDE THE GENERATOR?
//  The `ChordVoicingGenerator` is a general heuristic that works in ANY tuning,
//  but its "lowest chord-tone per string" shapes can come out thinner or less
//  idiomatic than the shapes a human would actually play — especially for the
//  bread-and-butter open chords. So the Chords tool uses this library as a
//  FALLBACK: when the active tuning is standard guitar AND the generator's shape
//  looks weak, it prefers the curated shape here. Outside standard tuning (custom
//  tunings, capos that change the open pitches) these shapes don't apply, so the
//  lookup simply returns `nil` and the generator's output is used.
//
//  Pure data + a lookup — no SwiftUI / AVFoundation. The shapes are pinned by
//  unit tests (e.g. C major must be the x32010 shape) so a typo can't silently
//  ship a wrong chord.
//
//  CHORD-BOX NOTATION REMINDER: each shape is `[Int?]` low → high (string 0 =
//  low E). `nil` = muted ("x"), `0` = open ("o"), `n` = fret n. So C major's
//  famous "x32010" reads, low → high: x(mute) 3 2 0 1 0.
//

import Foundation

/// The curated open-chord catalogue for standard guitar tuning.
///
/// An empty `enum` used as a namespace (same pattern as `InstrumentLibrary`): it
/// holds only `static` data + a `static` lookup, and can never be instantiated.
public enum StandardChordLibrary {

    /// The dictionary key: a chord is identified by its root pitch class plus its
    /// quality, exactly the two things the user picks in the UI. A `struct` key is
    /// the natural fit — `Hashable` is synthesized, so it drops straight into a
    /// `Dictionary` with no extra work.
    public struct Key: Hashable, Sendable {
        public let root: PitchClass
        public let quality: ChordQuality
        public init(root: PitchClass, quality: ChordQuality) {
            self.root = root
            self.quality = quality
        }
    }

    /// A tiny constructor so the table below reads like chord-box diagrams. It
    /// pairs a `(root, quality)` key with its `[Int?]` shape. `private` — it only
    /// exists to keep this file's literal table legible.
    private static func entry(
        _ root: PitchClass,
        _ quality: ChordQuality,
        _ frets: [Int?]
    ) -> (Key, ChordVoicing) {
        (Key(root: root, quality: quality), ChordVoicing(frets: frets))
    }

    /// The curated shapes. Built from an array of `entry(...)` pairs so the data
    /// reads top-to-bottom like a chord chart, then folded into a `Dictionary` for
    /// O(1) lookup.
    ///
    /// COVERAGE: the five classic open majors (C A G E D) and their minors where
    /// an open minor shape exists (Am Em Dm — there is no standard *open* C/G
    /// minor, so those are intentionally absent and fall through to the
    /// generator), plus the most-used open dominant 7ths (C7 A7 D7 E7 G7 B7) and a
    /// couple of open minor 7ths (Am7 Dm7 Em7). Every shape is a real, fingerable
    /// open chord a beginner will recognize.
    public static let shapes: [Key: ChordVoicing] = Dictionary(
        uniqueKeysWithValues: [
            // ── Open MAJORS (the "CAGED" open shapes) ───────────────────────────
            entry(.c, .major, [nil, 3, 2, 0, 1, 0]),   // x32010  (C E G C E)
            entry(.a, .major, [nil, 0, 2, 2, 2, 0]),   // x02220
            entry(.g, .major, [3, 2, 0, 0, 0, 3]),     // 320003
            entry(.e, .major, [0, 2, 2, 1, 0, 0]),     // 022100
            entry(.d, .major, [nil, nil, 0, 2, 3, 2]), // xx0232

            // ── Open MINORS (only those with a true open shape) ─────────────────
            entry(.a, .minor, [nil, 0, 2, 2, 1, 0]),   // x02210  (Am)
            entry(.e, .minor, [0, 2, 2, 0, 0, 0]),     // 022000  (Em)
            entry(.d, .minor, [nil, nil, 0, 2, 3, 1]), // xx0231  (Dm)

            // ── Open DOMINANT 7ths ──────────────────────────────────────────────
            entry(.c, .dominantSeventh, [nil, 3, 2, 3, 1, 0]), // x32310  (C7)
            entry(.a, .dominantSeventh, [nil, 0, 2, 0, 2, 0]), // x02020  (A7)
            entry(.d, .dominantSeventh, [nil, nil, 0, 2, 1, 2]), // xx0212 (D7)
            entry(.e, .dominantSeventh, [0, 2, 0, 1, 0, 0]),   // 020100  (E7)
            entry(.g, .dominantSeventh, [3, 2, 0, 0, 0, 1]),   // 320001  (G7)
            entry(.b, .dominantSeventh, [nil, 2, 1, 2, 0, 2]), // x21202  (B7)

            // ── Open MINOR 7ths ─────────────────────────────────────────────────
            entry(.a, .minorSeventh, [nil, 0, 2, 0, 1, 0]),    // x02010  (Am7)
            entry(.d, .minorSeventh, [nil, nil, 0, 2, 1, 1]),  // xx0211  (Dm7)
            entry(.e, .minorSeventh, [0, 2, 0, 0, 0, 0]),      // 020000  (Em7)
        ]
    )

    // MARK: - Lookup

    /// Look up a curated open shape for `(root, quality)`, or `nil` if this chord
    /// has no hand-authored entry (so the caller should use the generator instead).
    ///
    /// This is the seam the view-model uses: it only consults the library when the
    /// active tuning is standard guitar, so callers never get a shape that's wrong
    /// for the current tuning.
    public static func voicing(root: PitchClass, quality: ChordQuality) -> ChordVoicing? {
        shapes[Key(root: root, quality: quality)]
    }

    // MARK: - "Is this standard guitar tuning?" check

    /// The open-string note sequence that DEFINES standard guitar tuning, low →
    /// high: E2 A2 D3 G3 B3 E4. The curated shapes above are correct ONLY for this
    /// exact tuning, so the view-model checks a board's open strings against this
    /// before trusting the library.
    public static let standardGuitarOpenStrings: [Note] = [
        Note(pitchClass: .e, octave: 2),
        Note(pitchClass: .a, octave: 2),
        Note(pitchClass: .d, octave: 3),
        Note(pitchClass: .g, octave: 3),
        Note(pitchClass: .b, octave: 3),
        Note(pitchClass: .e, octave: 4),
    ]

    /// Whether `openStrings` is exactly standard guitar tuning. We compare the full
    /// `Note` (pitch class AND octave), because the curated frets assume those
    /// specific octaves — a ukulele's C, say, is the right pitch class but the
    /// wrong board entirely.
    public static func isStandardGuitar(openStrings: [Note]) -> Bool {
        openStrings == standardGuitarOpenStrings
    }
}
