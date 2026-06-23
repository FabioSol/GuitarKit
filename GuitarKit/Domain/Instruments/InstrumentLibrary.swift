//
//  InstrumentLibrary.swift
//  GuitarKit
//
//  The built-in catalogue of instruments and their preset tunings — the data the
//  picker lists and the tuner targets. This supersedes the `BuiltInTuning`
//  placeholder: standard-guitar EADGBE now lives here as one preset among many.
//
//  Pure data, no UI. Every tuning below is hand-checked against the real
//  instrument; the unit tests (InstrumentLibraryTests) pin the note sequences so
//  a typo can never silently ship a wrong tuning.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  HEADSTOCK LAYOUTS (documented here because JSON can't carry comments)
//
//  Each instrument names a `Headstocks/<name>.json` peg layout. Pegs are listed
//  in STRING ORDER (low → high) and normalized 0…1 within the head's box
//  ((0,0) = top-left, (1,1) = bottom-right). The standard guitar uses a "3 + 3"
//  arrangement (see HeadstockLayout.standardGuitar): the eye traces the strings
//  as a loop — low string bottom-left, up the left side, across the top, back
//  DOWN the right side, high string bottom-right. Most of our heads follow that
//  same two-column pattern (mirroring `HeadstockLayout.generic`). The two
//  "oddities" the issue calls out need hand-placement:
//
//    • BANJO (5-string): a 4-string head PLUS a 5th-string peg that sits partway
//      DOWN the neck on the bass side (it's a short drone string geared into the
//      side of the neck, not the head). So peg 0 (the high G drone, the LOWEST
//      index because strings are listed low→high by… see note below) is placed at
//      roughly x ≈ 0.06, y ≈ 0.55 — off on its own, down the left edge — while
//      the other four sit in the normal two-column head.
//
//    • VIOLIN (and the bowed family): a "2 + 2" PEGBOX, not a flat head — two
//      pegs on each side of a carved box. G and A pegs on one side, D and E on
//      the other, staggered up the box. We place them as two short columns.
//  ─────────────────────────────────────────────────────────────────────────────
//

import Foundation

// MARK: - Note spelling helpers

/// A file-private shorthand so the long tuning tables below read like the notes
/// a musician would say out loud, e.g. `n(.e, 2)` for "E2".
///
/// WHY A FREE FUNCTION (not a Note initializer)?
/// We don't want to pollute the public `Note` API with a terse alias; this helper
/// exists only to keep *this* file's big literal tables legible. `private`
/// scopes it to this file so it never leaks into the module's surface.
private func n(_ pitchClass: PitchClass, _ octave: Int) -> Note {
    Note(pitchClass: pitchClass, octave: octave)
}

// MARK: - InstrumentLibrary

/// A namespace (an empty `enum`, so it can never be instantiated) holding the
/// built-in instrument catalogue and the lookups the app needs.
///
/// WHY AN ENUM NAMESPACE?
/// We want `InstrumentLibrary.all` and `InstrumentLibrary.default` as type-level
/// values, never an *instance* of a library. An `enum` with no cases can't be
/// constructed (there's no value to make), which expresses "this is a bag of
/// statics" more honestly than a `struct` would.
public enum InstrumentLibrary {

    // MARK: Guitars

    /// Standard 6-string guitar. Home tuning EADGBE plus the most-used presets.
    ///
    /// PRESETS (low → high):
    ///   • Standard    E2 A2 D3 G3 B3 E4
    ///   • Drop D      D2 A2 D3 G3 B3 E4  (only the 6th string drops a whole tone)
    ///   • Open G      D2 G2 D3 G3 B3 D4  (open strings sound a G-major chord)
    ///   • DADGAD      D2 A2 D3 G3 A3 D4  (a Celtic/modal "alternate" staple)
    ///   • Half-Step Down  Eb2 Ab2 Db3 Gb3 Bb3 Eb4 (everything down one semitone)
    public static let guitar6 = Instrument(
        id: "guitar-6",
        name: "Guitar",
        category: .guitar,
        tunings: [
            Tuning(name: "Standard", category: .standard, strings: [
                n(.e, 2), n(.a, 2), n(.d, 3), n(.g, 3), n(.b, 3), n(.e, 4)
            ]),
            Tuning(name: "Drop D", category: .drop, strings: [
                n(.d, 2), n(.a, 2), n(.d, 3), n(.g, 3), n(.b, 3), n(.e, 4)
            ]),
            Tuning(name: "Open G", category: .open, strings: [
                n(.d, 2), n(.g, 2), n(.d, 3), n(.g, 3), n(.b, 3), n(.d, 4)
            ]),
            Tuning(name: "DADGAD", category: .alternate, strings: [
                n(.d, 2), n(.a, 2), n(.d, 3), n(.g, 3), n(.a, 3), n(.d, 4)
            ]),
            Tuning(name: "Half-Step Down", category: .alternate, strings: [
                // Sharps are how `PitchClass` spells the black keys; Eb == D#, etc.
                n(.dSharp, 2), n(.gSharp, 2), n(.cSharp, 3),
                n(.fSharp, 3), n(.aSharp, 3), n(.dSharp, 4)
            ])
        ],
        headstockSpecName: "guitar"
    )

    /// 7-string guitar: a standard 6-string with an extra LOW B below the low E.
    /// Home tuning B1 E2 A2 D3 G3 B3 E4 ("BEADGBE"). Drop A lowers that 7th to A1.
    public static let guitar7 = Instrument(
        id: "guitar-7",
        name: "7-String Guitar",
        category: .guitar,
        tunings: [
            Tuning(name: "Standard", category: .standard, strings: [
                n(.b, 1), n(.e, 2), n(.a, 2), n(.d, 3), n(.g, 3), n(.b, 3), n(.e, 4)
            ]),
            Tuning(name: "Drop A", category: .drop, strings: [
                n(.a, 1), n(.e, 2), n(.a, 2), n(.d, 3), n(.g, 3), n(.b, 3), n(.e, 4)
            ])
        ],
        headstockSpecName: "guitar-7"
    )

    // MARK: Basses

    /// 4-string electric bass. Home tuning E1 A1 D2 G2 — one octave below the
    /// guitar's bottom four strings. Drop D lowers the 4th string to D1.
    public static let bass4 = Instrument(
        id: "bass-4",
        name: "Bass",
        category: .bass,
        tunings: [
            Tuning(name: "Standard", category: .standard, strings: [
                n(.e, 1), n(.a, 1), n(.d, 2), n(.g, 2)
            ]),
            Tuning(name: "Drop D", category: .drop, strings: [
                n(.d, 1), n(.a, 1), n(.d, 2), n(.g, 2)
            ])
        ],
        headstockSpecName: "bass-4"
    )

    /// 5-string bass: a 4-string with an extra LOW B below the E.
    /// Home tuning B0 E1 A1 D2 G2.
    public static let bass5 = Instrument(
        id: "bass-5",
        name: "5-String Bass",
        category: .bass,
        tunings: [
            Tuning(name: "Standard", category: .standard, strings: [
                n(.b, 0), n(.e, 1), n(.a, 1), n(.d, 2), n(.g, 2)
            ])
        ],
        headstockSpecName: "bass-5"
    )

    // MARK: Ukulele

    /// Soprano/concert ukulele in standard "reentrant" GCEA tuning.
    ///
    /// THE ODDITY (reentrant tuning): the 4th string (G4) is HIGHER in pitch than
    /// the 3rd (C4) — the strings are NOT in low-to-high pitch order on the
    /// instrument. We still list `strings` in *physical* order (4th string first),
    /// so the note sequence is G4 C4 E4 A4 even though G4 > C4. The headstock and
    /// tuner index strings physically, so this is correct — but it's why the test
    /// checks the literal G4 C4 E4 A4 sequence rather than assuming ascending.
    public static let ukulele = Instrument(
        id: "ukulele",
        name: "Ukulele",
        category: .ukulele,
        tunings: [
            Tuning(name: "Standard (Reentrant)", category: .standard, strings: [
                n(.g, 4), n(.c, 4), n(.e, 4), n(.a, 4)
            ])
        ],
        headstockSpecName: "ukulele"
    )

    // MARK: Banjo (oddity: the 5th drone peg)

    /// 5-string banjo in "Open G" tuning: g4 D3 G3 B3 D4.
    ///
    /// THE ODDITY: the 5th string is a SHORT high drone (g4) whose peg is geared
    /// into the SIDE of the neck about a fifth of the way down, not on the head.
    /// We list it first (it's string index 0) so its peg can be hand-placed down
    /// the neck in `banjo-5.json`; the other four sit in the normal head. Like the
    /// ukulele this is reentrant — the drone g4 is the highest-pitched string.
    public static let banjo5 = Instrument(
        id: "banjo-5",
        name: "5-String Banjo",
        category: .banjo,
        tunings: [
            Tuning(name: "Open G", category: .open, strings: [
                n(.g, 4), n(.d, 3), n(.g, 3), n(.b, 3), n(.d, 4)
            ])
        ],
        headstockSpecName: "banjo-5"
    )

    // MARK: Violin (oddity: the 2+2 pegbox)

    /// Violin in standard tuning G3 D4 A4 E5 — strings a perfect FIFTH apart
    /// (unlike the guitar's fourths). Pegs sit in a carved 2+2 pegbox rather than
    /// a flat head (see the header comment and `violin.json`).
    public static let violin = Instrument(
        id: "violin",
        name: "Violin",
        category: .orchestral,
        tunings: [
            Tuning(name: "Standard", category: .standard, strings: [
                n(.g, 3), n(.d, 4), n(.a, 4), n(.e, 5)
            ])
        ],
        headstockSpecName: "violin"
    )

    // MARK: The catalogue

    /// Every built-in instrument, in the canonical order the picker should show
    /// them. `static let` so it's computed once and shared — pure value data, so
    /// there's no shared-mutable-state concern.
    public static let all: [Instrument] = [
        guitar6,
        guitar7,
        bass4,
        bass5,
        ukulele,
        banjo5,
        violin
    ]

    /// The cold-start default the app opens to (PRD: "guitar = cold-start
    /// default"). The standard 6-string guitar.
    public static let `default`: Instrument = guitar6

    // MARK: Lookups

    /// Find an instrument by its stable `id` ("guitar-6", "violin"…), or `nil` if
    /// no such entry exists. This is the seam persistence uses to restore the
    /// user's last-used instrument from a saved id string.
    ///
    /// `first(where:)` is a standard-library higher-order function: it walks `all`
    /// and returns the first element whose closure returns `true`, or `nil`.
    public static func instrument(id: String) -> Instrument? {
        all.first { $0.id == id }
    }
}
