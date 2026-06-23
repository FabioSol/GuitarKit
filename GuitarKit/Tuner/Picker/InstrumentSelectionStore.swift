//
//  InstrumentSelectionStore.swift
//  GuitarKit
//
//  The small, persistent memory of the TUNER'S instrument/tuning picker. It
//  answers two questions across app launches:
//    1. "Which instrument + tuning was the player last using?" — so we restore it
//       on relaunch instead of always cold-starting on standard guitar.
//    2. "Which instruments does this player reach for most?" — so the picker's
//       pinned "Most-used" group at the top is ordered by real habits.
//
//  WHY A SEPARATE STORE FROM `SettingsStore`?
//  `SettingsStore` holds GLOBAL preferences (reference pitch, haptics, theme…) —
//  things that apply app-wide. The picker's memory is a different concern: it's
//  the Tuner tool's own per-tool state (PRD: "per-tool ephemeral choices stay
//  inside their tool"). Keeping it in its own object means the picker can be
//  understood, tested, and evolved without touching the settings surface. But we
//  COPY `SettingsStore`'s persistence *pattern* exactly: `@Observable`, injectable
//  `UserDefaults`, `didSet` writes, `object(forKey:)` reads, namespaced keys.
//
//  HOW PERSISTENCE WORKS HERE (same shape as SettingsStore):
//  Each persisted value is a stored property whose `didSet` writes it to
//  `UserDefaults` under a stable, namespaced key. The initialiser reads every key
//  back, falling back to a sensible default when the key was never written (a
//  fresh install). Everything stays on-device — there's no network anywhere here,
//  which the PRD requires ("usage counts… all on-device").
//

import Foundation
import Observation

/// The picker's persistent selection + usage memory, observable and
/// UserDefaults-backed.
///
/// `@MainActor` — like `SettingsStore`, this is read and written from the UI
/// (the picker sheet and the Tuner face), so pinning it to the main actor keeps
/// every access safe with no locks. `@Observable` makes SwiftUI re-render the
/// views that read a changed value. `final` because we never subclass it.
@MainActor
@Observable
final class InstrumentSelectionStore {

    // MARK: Storage keys
    //
    // Every persisted value gets a stable, namespaced key, gathered here in one
    // place so there are no stringly-typed typos scattered through the `didSet`s
    // (the same trick `SettingsStore.Key` uses). NEVER rename these once shipped,
    // or the player loses their restored selection / usage history.
    private enum Key {
        static let lastInstrumentID = "guitarkit.picker.lastInstrumentID"
        static let lastTuningName   = "guitarkit.picker.lastTuningName"
        static let usageCounts      = "guitarkit.picker.usageCounts"
    }

    // MARK: Seed (the "prior" that washes out)
    //
    // PRD: the Most-used group is "seeded with sensible defaults that wash out as
    // real usage accumulates". We model that as a tiny PRIOR count granted to a
    // few common instruments, so a fresh install still shows a sensible order
    // (guitar first, then bass, then ukulele) — but because the prior is small,
    // a handful of real selections quickly overtakes it. The seed is applied at
    // *ranking* time (see `mostUsedInstrumentIDs`), NOT written to storage, so we
    // can always tell a real selection from the seed and the seed can evolve in a
    // later version without migrating anyone's data.
    private enum Seed {
        /// Instrument id → its prior count. Small numbers on purpose: a couple of
        /// real selections of any other instrument will out-rank the seeds.
        static let priors: [String: Int] = [
            "guitar-6": 3,   // the cold-start default ranks first on a fresh install
            "bass-4":   2,
            "ukulele":  1
        ]
    }

    // MARK: The defaults store (injected)

    /// Which `UserDefaults` to persist into. Production uses `.standard`; tests
    /// pass an isolated named suite so they never touch real preferences.
    ///
    /// `@ObservationIgnored` keeps this out of SwiftUI's change tracking — it's
    /// infrastructure, not a value any view should re-render on.
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Last-used selection

    /// The id of the instrument the player last selected (e.g. "guitar-6"), or
    /// `nil` on a fresh install (nothing chosen yet). Stored as a plain `String`
    /// because `UserDefaults` can't hold an `Instrument` directly — and the id is
    /// designed to be stable across launches exactly so it can be persisted.
    var lastInstrumentID: String? {
        didSet { defaults.set(lastInstrumentID, forKey: Key.lastInstrumentID) }
    }

    /// The NAME of the tuning the player last selected on that instrument (e.g.
    /// "Drop D"), or `nil` if none recorded. We persist the name (not an index)
    /// because names are stable and human-meaningful even if a preset list is
    /// reordered; resolving it back to a `Tuning` happens in `restoredTuning`.
    var lastTuningName: String? {
        didSet { defaults.set(lastTuningName, forKey: Key.lastTuningName) }
    }

    // MARK: Usage counts

    /// How many times each instrument has been selected, keyed by instrument id.
    /// This is the raw signal behind the Most-used ordering. We store it as a
    /// `[String: Int]` dictionary, which `UserDefaults` can persist directly (a
    /// dictionary of plist-friendly types). Only REAL selections live here; the
    /// seed prior is layered on at ranking time, never written in.
    ///
    /// `private(set)` because the only legitimate way to change a count is through
    /// `recordSelection` — callers read it (e.g. tests) but can't poke arbitrary
    /// values in.
    private(set) var usageCounts: [String: Int] {
        didSet { defaults.set(usageCounts, forKey: Key.usageCounts) }
    }

    // MARK: Init

    /// Build the store, loading the last selection + usage counts from `defaults`
    /// (or their empty/`nil` defaults on a fresh install).
    ///
    /// - Parameter defaults: where to persist. Defaults to `.standard`.
    ///
    /// NOTE ON THE DEFAULT ARGUMENT: `UserDefaults.standard` is safe as a default
    /// argument even though this is a `@MainActor` type — it's a plain Foundation
    /// singleton, not a main-actor-isolated expression, so it doesn't trip the
    /// "main-actor default argument" warning this project is careful about. (For a
    /// main-actor value we'd default the parameter to `nil` and resolve inside the
    /// init instead.)
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Read each value back. `string(forKey:)` already returns `nil` for a
        // missing key, which is exactly the "nothing chosen yet" we want for the
        // two last-used properties — so we can read them straight across.
        //
        // We assign DIRECTLY to the stored properties' backing — but assigning a
        // property fires its `didSet`, which would write straight back. For the
        // two String? values that's a harmless idempotent write. For usageCounts
        // it's likewise harmless. So we just assign normally and accept the one
        // cheap re-write (the same approach `SettingsStore.init` takes).
        self.lastInstrumentID = defaults.string(forKey: Key.lastInstrumentID)
        self.lastTuningName = defaults.string(forKey: Key.lastTuningName)

        // Usage counts: `dictionary(forKey:)` returns `[String: Any]?`. We cast
        // the values to `Int` (the only thing we ever store) and drop anything
        // that doesn't fit, then default to an empty map on a fresh install.
        if let raw = defaults.dictionary(forKey: Key.usageCounts) {
            self.usageCounts = raw.compactMapValues { $0 as? Int }
        } else {
            self.usageCounts = [:]
        }
    }

    // MARK: Recording a selection

    /// Record that the player just picked `instrumentID` + `tuningName`. This is
    /// the single entry point the picker calls on every selection. It does two
    /// things together so they can never drift apart:
    ///   1. remembers this as the last-used instrument + tuning (for restore), and
    ///   2. increments this instrument's usage count (for Most-used ordering).
    ///
    /// - Parameters:
    ///   - instrumentID: the chosen instrument's stable id (e.g. "bass-4").
    ///   - tuningName: the chosen tuning's display name (e.g. "Drop D").
    func recordSelection(instrumentID: String, tuningName: String) {
        lastInstrumentID = instrumentID
        lastTuningName = tuningName

        // Increment the count. `usageCounts[id, default: 0]` reads the current
        // count (or 0 if this instrument was never selected) and we add one. The
        // `didSet` on `usageCounts` then persists the whole dictionary.
        usageCounts[instrumentID, default: 0] += 1
    }

    // MARK: Most-used ordering

    /// The instrument ids the player uses most, best-first, capped at `limit`.
    /// This drives the picker's pinned "Most-used" group at the top of the sheet.
    ///
    /// HOW THE SEED "WASHES OUT":
    /// We rank by *effective* count = real selections + the seed prior (0 for
    /// instruments with no prior). On a fresh install the only non-zero scores are
    /// the seeds, so the group is non-empty and sensibly ordered (guitar, bass,
    /// ukulele). As the player records real selections, those real counts grow and
    /// quickly dominate the small priors — so the list naturally shifts to reflect
    /// actual habits. We restrict the result to instruments that still EXIST in the
    /// library (so a removed instrument can't haunt the list) and, in canonical
    /// order, break ties by that library order for a stable, predictable result.
    ///
    /// - Parameter limit: the maximum number of ids to return (the group size).
    func mostUsedInstrumentIDs(limit: Int) -> [String] {
        // Build the effective score for every instrument currently in the library.
        // Walking `InstrumentLibrary.all` (not the dictionary keys) keeps the set
        // bounded to real instruments and gives us a canonical tiebreak order.
        let scored: [(id: String, score: Int, order: Int)] =
            InstrumentLibrary.all.enumerated().map { index, instrument in
                let real = usageCounts[instrument.id] ?? 0
                let prior = Seed.priors[instrument.id] ?? 0
                return (id: instrument.id, score: real + prior, order: index)
            }

        // Keep only instruments with a positive score (real use OR a seed prior),
        // so an unused, unseeded instrument never pads the Most-used group.
        let ranked = scored
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                // Higher score first; on a tie, earlier canonical order first so
                // the ordering is deterministic (no arbitrary dictionary order).
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.order < rhs.order
            }

        // Take the top `limit` ids. `prefix` is safe even if fewer exist.
        return ranked.prefix(max(0, limit)).map(\.id)
    }

    // MARK: Restoring the persisted selection

    /// The instrument to open the Tuner on, resolved from the persisted id. Falls
    /// back to `InstrumentLibrary.default` (standard guitar, the cold-start
    /// default) when nothing was stored yet, OR when the stored id no longer maps
    /// to a real instrument (e.g. an instrument removed in a later app version).
    /// So this NEVER returns nil — the Tuner always has something to show.
    func restoredInstrument() -> Instrument {
        guard
            let id = lastInstrumentID,
            let instrument = InstrumentLibrary.instrument(id: id)
        else {
            return InstrumentLibrary.default
        }
        return instrument
    }

    /// The tuning to open `instrument` on, resolved from the persisted tuning
    /// name. Falls back to the instrument's own default (home) tuning when nothing
    /// was stored, when the stored name doesn't match any of this instrument's
    /// presets (e.g. a tuning the instrument doesn't have, or a stale name), or in
    /// the never-expected case of an instrument with no presets.
    ///
    /// - Parameter instrument: the instrument whose presets we resolve against —
    ///   normally the result of `restoredInstrument()`.
    func restoredTuning(for instrument: Instrument) -> Tuning {
        if
            let name = lastTuningName,
            let match = instrument.tunings.first(where: { $0.name == name })
        {
            return match
        }
        // No stored name, or it didn't match this instrument's presets: use the
        // home tuning. The final `?? ...` guards the (never-shipped) empty-tunings
        // case so this can't crash — same defensive placeholder TuningSessionModel
        // uses.
        return instrument.defaultTuning
            ?? Tuning(name: "Standard", category: .standard, strings: [])
    }
}
