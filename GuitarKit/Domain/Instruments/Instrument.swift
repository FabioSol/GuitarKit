//
//  Instrument.swift
//  GuitarKit
//
//  The pure model of a tunable instrument: what it is, how many strings it has,
//  which preset tunings it ships with, and which headstock art describes its
//  peg layout.
//
//  Like the rest of `Domain/`, this file has NO UIKit / SwiftUI / AVFoundation
//  imports on purpose. Everything here is plain value-type data the tuner reads;
//  keeping it free of UI is what lets us unit-test the instrument catalogue in
//  isolation (see InstrumentLibraryTests).
//

import Foundation

// MARK: - InstrumentCategory

/// The broad family an instrument belongs to.
///
/// WHY AN ENUM?
/// Just like `PitchClass`, the set of instrument families is a *closed list* —
/// we know up front the categories the app supports. An `enum` makes invalid
/// categories unrepresentable and gives us exhaustive `switch` checking if a
/// later slice (e.g. the picker UI) needs to branch per family.
///
/// `String` raw values: declaring `: String` gives each case a stable text name
/// ("guitar", "bass", …). That's handy if we ever persist a chosen instrument or
/// drive analytics-free debug logging by family, and it costs us nothing.
///
/// `CaseIterable` synthesizes `allCases` so the picker can list every family in
/// declaration order. `Sendable` is free safety for a simple value type and is
/// good hygiene in modern concurrency-checked Swift.
public enum InstrumentCategory: String, CaseIterable, Sendable {
    case guitar
    case bass
    case ukulele
    case mandolin
    case banjo
    case orchestral   // bowed strings: violin / viola / cello
}

// MARK: - TuningCategory

/// How a preset tuning relates to the instrument's "home" tuning.
///
/// The PRD groups presets into these four buckets so the picker can show them
/// under labelled sections (Standard / Drop / Open / Alternate). Modelling the
/// bucket on the `Tuning` itself — rather than, say, a string label the UI has
/// to parse — keeps the grouping a *typed* fact the data owns.
///
/// MEANINGS (for the learner):
///   • `standard`  — the instrument's canonical tuning (guitar EADGBE, bass EADG).
///   • `drop`      — the lowest string dropped a tone (Drop D, Drop C…), so a
///                   power chord can be fingered with one barred finger.
///   • `open`      — the open strings sound a full chord (Open G, Open D…), the
///                   slide-guitar staple.
///   • `alternate` — anything else musically useful (DADGAD, half-step down…).
public enum TuningCategory: String, CaseIterable, Sendable {
    case standard
    case drop
    case open
    case alternate
}

// MARK: - Tuning

/// A named preset tuning: a list of open-string notes plus the category it files
/// under. This is the exact shape the PRD's "Music & tuning domain" section
/// specifies: `Tuning = { name, category, strings: [Note] }`.
///
/// WHY A STRUCT?
/// A tuning is a small, identity-less bundle of values — two "Drop D" tunings
/// with the same notes are interchangeable. That's the textbook case for a
/// value-type `struct`: copied on assignment, with synthesized memberwise
/// `Equatable` (so tests can assert `tuning.strings == [...]`). `Sendable` again
/// rides for free on a pure value type.
///
/// STRING ORDER: `strings` is always low → high — the same order a guitarist
/// reads them (6th string first) and the same order `PitchCalculator.targets`
/// and the headstock peg array expect. Keeping one consistent order everywhere
/// is what lets a string's index mean the same thing across the whole app.
public struct Tuning: Equatable, Sendable {
    /// Display name, e.g. "Standard", "Drop D", "DADGAD".
    public let name: String
    /// Which picker section this preset files under.
    public let category: TuningCategory
    /// Open-string notes, low → high.
    public let strings: [Note]

    /// Explicit `public init` because a struct's synthesized initializer is
    /// `internal` by default — invisible outside the module. The library and the
    /// tests both build `Tuning`s directly, so the initializer must be public.
    public init(name: String, category: TuningCategory, strings: [Note]) {
        self.name = name
        self.category = category
        self.strings = strings
    }

    /// How many strings this tuning covers — a convenience for asserting the
    /// "every tuning in an instrument shares its string count" invariant.
    /// Computed (no stored memory) because it's purely a function of `strings`.
    public var stringCount: Int { strings.count }
}

// MARK: - Instrument

/// One catalogue entry: a specific instrument with a FIXED string count, the set
/// of preset tunings it ships with, and the name of its headstock spec JSON.
///
/// WHY IS STRING COUNT FIXED PER ENTRY?
/// The PRD decided that a 7-string guitar and a 6-string guitar are *separate*
/// catalogue entries, not one entry whose string count varies. That keeps the
/// headstock layout (peg positions) and the tuner's string indices stable for a
/// given entry — you never have to redraw pegs just because you switched preset.
/// So every `Tuning` in `tunings` MUST have the same `stringCount`; `stringCount`
/// below reads it off the first tuning, and the tests assert the invariant holds.
///
/// `Identifiable`: gives the type an `id`, which SwiftUI's `ForEach`/pickers use
/// to track rows without us hand-writing tags. We use a stable `String` id
/// ("guitar-6", "bass-5", …) rather than a `UUID` so the id survives app
/// launches — important once we persist the user's last-used instrument.
///
/// `Equatable` for tests; `Sendable` because every stored property is itself a
/// pure value type, so an `Instrument` is safe to hand across actors.
public struct Instrument: Identifiable, Equatable, Sendable {
    /// Stable, human-meaningful identifier ("guitar-6", "violin"…). Stable across
    /// launches so it can be persisted/restored.
    public let id: String
    /// Display name for the picker ("Guitar", "5-String Bass"…).
    public let name: String
    /// The broad family (drives section grouping / iconography later).
    public let category: InstrumentCategory
    /// Preset tunings, in the order the picker should list them. By convention the
    /// first entry is the instrument's "home"/default tuning.
    public let tunings: [Tuning]
    /// The base name of this instrument's headstock JSON under `Headstocks/`
    /// (e.g. "guitar" → `Headstocks/guitar.json`). `HeadstockSpec.load(name)`
    /// turns this into the peg layout + art for the hero view.
    public let headstockSpecName: String

    /// Explicit public init (synthesized one would be internal-only).
    public init(
        id: String,
        name: String,
        category: InstrumentCategory,
        tunings: [Tuning],
        headstockSpecName: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.tunings = tunings
        self.headstockSpecName = headstockSpecName
    }

    /// The instrument's fixed string count, read off its first preset.
    ///
    /// WHY COMPUTED FROM THE FIRST TUNING?
    /// Because the count is an invariant of the *entry* (all presets share it),
    /// storing it separately would just be a second source of truth to keep in
    /// sync. We instead derive it from the first preset and let the tests pin the
    /// invariant that every other preset agrees. `first?.stringCount ?? 0` guards
    /// the (never-expected) empty-tunings case so this can't crash.
    public var stringCount: Int { tunings.first?.stringCount ?? 0 }

    /// The instrument's default tuning — its first preset by convention. Optional
    /// because `tunings` *could* be empty in principle; in the shipped library it
    /// never is.
    public var defaultTuning: Tuning? { tunings.first }
}
