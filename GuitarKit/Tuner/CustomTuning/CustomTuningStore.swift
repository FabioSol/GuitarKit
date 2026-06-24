//
//  CustomTuningStore.swift
//  GuitarKit
//
//  The persistent home of the player's OWN custom tunings (slice #12, PRD stories
//  26–32). It answers one question across launches, per instrument:
//    "Which custom tunings has the player saved for THIS instrument?"
//  — so the picker can list them under a "Custom" section and the editor can add,
//  replace, and delete them.
//
//  WHY A SEPARATE STORE (not folded into InstrumentSelectionStore)?
//  Custom tunings are their own concern with their own shape (a *list per
//  instrument*, not a single last-used value). Keeping them here lets that
//  concern be understood, tested, and evolved on its own. But we COPY
//  `InstrumentSelectionStore`'s persistence *pattern* exactly: `@Observable`,
//  an injectable `UserDefaults`, namespaced keys, everything on-device.
//
//  THE PERSISTENCE PROBLEM — `Tuning`/`Note` are NOT `Codable`:
//  Those are shared domain types in `Domain/`, and this slice must not edit them.
//  So instead of trying to encode a `Tuning` directly, we define our OWN tiny
//  `Codable` data-transfer object (DTO) here — `CustomTuningDTO` — that stores
//  just what we need (the tuning's name + each string as a MIDI number), JSON-
//  encode a dictionary of those into `UserDefaults`, and convert DTO ⇄ `Tuning`
//  at the edges. MIDI numbers are the perfect storage form: a single `Int` that
//  round-trips losslessly through `Note.from(midiNumber:)` / `note.midiNumber`.
//
//  WHY CATEGORY `.alternate` FOR CUSTOM TUNINGS?
//  `TuningCategory` has no `.custom` case (it's a shared enum we must not edit:
//  .standard/.drop/.open/.alternate). `.alternate` — "anything else musically
//  useful" — is the closest honest fit, so every `Tuning` we hand back uses it.
//  The "Custom" *grouping* in the picker therefore can't come from the category;
//  it comes from the fact that these tunings live in THIS store. The picker asks
//  this store (`tunings(forInstrumentID:)`) for the Custom section's contents
//  separately from the instrument's built-in presets — see the integration notes
//  in the editor file. (If a future slice adds a real `.custom` case to the
//  shared enum, switch the `category:` below to it; nothing else here changes.)
//

import Foundation
import Observation

// MARK: - CustomTuningDTO

/// The on-disk shape of one saved custom tuning. A small `Codable` value we own,
/// kept deliberately separate from the un-`Codable` shared `Tuning` so persisting
/// never requires touching the domain types.
///
/// `Codable` = Swift can auto-generate JSON encode/decode for it because every
/// stored property is itself codable (`String` + `[Int]`). `Equatable`/`Sendable`
/// ride along for free and help the tests.
///
/// `private` to the file: nothing outside this store should know our storage
/// format. Callers deal only in `Tuning`s; the DTO is an internal detail.
private struct CustomTuningDTO: Codable, Equatable, Sendable {
    /// The tuning's display name (e.g. "DADGAD"). This is also the IDENTITY we
    /// add/replace/delete by — two custom tunings on the same instrument can't
    /// share a name (saving the same name replaces).
    let name: String
    /// Each open string stored as its MIDI number, low → high. A MIDI number is a
    /// lossless, plist-friendly `Int` that converts straight back to a `Note`.
    let stringMidiNumbers: [Int]

    /// Build a DTO from a domain `Tuning` (the "to storage" direction). We read
    /// each string's `midiNumber` and drop the category, because every custom
    /// tuning is re-tagged `.alternate` on the way back out (see file header).
    init(from tuning: Tuning) {
        self.name = tuning.name
        self.stringMidiNumbers = tuning.strings.map(\.midiNumber)
    }

    /// Rebuild a domain `Tuning` from this DTO (the "from storage" direction).
    /// Each stored MIDI number becomes a `Note` again, and we stamp the
    /// `.alternate` category (the closest fit for "custom" in the shared enum).
    func toTuning() -> Tuning {
        Tuning(
            name: name,
            category: .alternate,
            strings: stringMidiNumbers.map { Note.from(midiNumber: $0) }
        )
    }
}

// MARK: - CustomTuningStore

/// The player's saved custom tunings, observable and `UserDefaults`-backed,
/// organised per instrument.
///
/// `@MainActor` — like the other stores, it's read and written from the UI (the
/// picker and the editor sheet), so pinning it to the main actor keeps every
/// access safe without locks. `@Observable` makes SwiftUI re-render the picker
/// when a tuning is saved or deleted. `final` because we never subclass it.
@MainActor
@Observable
final class CustomTuningStore {

    // MARK: Storage key

    /// The single namespaced key under which we persist EVERY instrument's custom
    /// tunings, as one JSON blob. Gathered here so there's no stringly-typed typo,
    /// matching the other stores' `Key` enum. NEVER rename once shipped, or the
    /// player loses their saved tunings.
    private enum Key {
        static let customTunings = "guitarkit.customTunings.v1"
        /// Where we stash a blob we COULDN'T decode, so corrupt/old data is never
        /// silently destroyed (see the init). A future migration can read this.
        static let corruptBackup = "guitarkit.customTunings.v1.corrupt-backup"
    }

    // MARK: The defaults store (injected)

    /// Which `UserDefaults` to persist into. Production uses `.standard`; tests
    /// pass an isolated named suite so they never touch real preferences.
    ///
    /// `@ObservationIgnored` keeps this plumbing out of SwiftUI's change tracking.
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: In-memory model

    /// The whole library, in memory: instrument id → that instrument's saved
    /// tunings (as DTOs, in insertion order). This is the single source of truth
    /// the public methods read and mutate; every mutation re-persists the whole
    /// map via `persist()`.
    ///
    /// We keep it `private` and expose only the `Tuning`-shaped API below, so the
    /// DTO storage format stays an internal detail. `@ObservationIgnored` because
    /// SwiftUI observes through our *methods'* effects (a save/delete reassigns
    /// nothing observable directly); the picker re-reads `tunings(forInstrumentID:)`
    /// after calling a mutator, so we don't need fine-grained observation here.
    @ObservationIgnored private var tuningsByInstrument: [String: [CustomTuningDTO]]

    // MARK: Init

    /// Build the store, loading any previously-saved custom tunings from
    /// `defaults` (or an empty library on a fresh install).
    ///
    /// - Parameter defaults: where to persist. Defaults to `.standard`.
    ///
    /// NOTE ON THE DEFAULT ARGUMENT: `UserDefaults.standard` is a plain Foundation
    /// singleton, not a main-actor-isolated expression, so it's safe as a default
    /// argument even on this `@MainActor` type (same reasoning as the other
    /// stores). A genuinely main-actor value would have to default to `nil` and be
    /// resolved inside the init instead — the project's documented gotcha.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load + decode the JSON blob. We read the raw `Data`, then try to JSON-
        // decode it into our `[String: [CustomTuningDTO]]` map. ANY failure falls
        // back to an empty library rather than crashing — refusing to launch over
        // unreadable tunings would be far worse.
        //
        // BUT we distinguish the two failure cases:
        //   • NO data at all → fresh install: start empty, nothing to preserve.
        //   • data present but UNDECODABLE → corrupt, or saved by an incompatible
        //     future/old schema. We start empty so the app works, but we FIRST copy
        //     the raw blob to a backup key. Without this, the very next save would
        //     overwrite the original key and silently destroy the player's tunings
        //     forever; the backup keeps them recoverable by a later migration.
        let data = defaults.data(forKey: Key.customTunings)
        if
            let data,
            let decoded = try? JSONDecoder().decode([String: [CustomTuningDTO]].self, from: data)
        {
            self.tuningsByInstrument = decoded
        } else {
            if let data {
                // Preserve the unreadable blob before we proceed empty.
                defaults.set(data, forKey: Key.corruptBackup)
            }
            self.tuningsByInstrument = [:]
        }
    }

    // MARK: Reading

    /// The custom tunings saved for one instrument, as domain `Tuning`s, in the
    /// order they were saved. Returns an empty array when the instrument has none
    /// (or was never seen). This is what the picker calls to fill its "Custom"
    /// section for a given instrument.
    ///
    /// - Parameter instrumentID: the instrument's stable id (e.g. "guitar-6").
    func tunings(forInstrumentID instrumentID: String) -> [Tuning] {
        // Look up this instrument's DTOs (or an empty list), then convert each
        // back into a `Tuning`. `map(\.toTuning ...)` would need a method
        // reference; we use a trailing closure for clarity.
        let dtos = tuningsByInstrument[instrumentID] ?? []
        return dtos.map { $0.toTuning() }
    }

    // MARK: Writing

    /// Add a custom tuning for an instrument, or REPLACE the existing one with the
    /// same name (so re-saving an edited tuning under its old name updates it in
    /// place rather than creating a duplicate). Identity is the tuning's `name`.
    ///
    /// - Parameters:
    ///   - tuning: the tuning to store. Its category is ignored on the way in (we
    ///     re-tag `.alternate` on the way out); only name + strings are kept.
    ///   - instrumentID: the instrument this tuning belongs to.
    func save(_ tuning: Tuning, forInstrumentID instrumentID: String) {
        let dto = CustomTuningDTO(from: tuning)

        // Start from this instrument's current list (or an empty one).
        var list = tuningsByInstrument[instrumentID] ?? []

        // Replace-by-name if a tuning with this name already exists; otherwise
        // append. `firstIndex(where:)` finds the existing slot, if any.
        if let existing = list.firstIndex(where: { $0.name == dto.name }) {
            list[existing] = dto
        } else {
            list.append(dto)
        }

        tuningsByInstrument[instrumentID] = list
        persist()
    }

    /// Delete the custom tuning with the given name from an instrument (the
    /// picker's swipe-to-delete, story 32). A no-op if no tuning by that name
    /// exists, so deleting twice is harmless.
    ///
    /// - Parameters:
    ///   - name: the display name of the tuning to remove (e.g. "DADGAD").
    ///   - instrumentID: the instrument to remove it from.
    func delete(named name: String, forInstrumentID instrumentID: String) {
        // Nothing saved for this instrument → nothing to delete.
        guard var list = tuningsByInstrument[instrumentID] else { return }

        // Drop every DTO matching the name (there's at most one by our
        // save-replaces-by-name rule, but `removeAll` is robust either way).
        list.removeAll { $0.name == name }

        // If that emptied the instrument's list, drop the key entirely so the
        // stored map doesn't accumulate empty arrays.
        if list.isEmpty {
            tuningsByInstrument[instrumentID] = nil
        } else {
            tuningsByInstrument[instrumentID] = list
        }

        persist()
    }

    // MARK: Persistence

    /// Encode the whole in-memory library to JSON and write it under our key. We
    /// re-write the ENTIRE map on every mutation: the data is tiny (a handful of
    /// tunings of a few ints each), so the simplicity of one blob beats any
    /// per-instrument key scheme. An encoding failure is swallowed (it can't
    /// happen for these plain `Codable` types, but we never want a save to crash).
    private func persist() {
        guard let data = try? JSONEncoder().encode(tuningsByInstrument) else { return }
        defaults.set(data, forKey: Key.customTunings)
    }
}
