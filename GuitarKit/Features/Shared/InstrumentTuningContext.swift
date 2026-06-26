//
//  InstrumentTuningContext.swift
//  GuitarKit — shared tool support
//
//  The tuning-derivation the Chords and Scales tools BOTH need, in one place.
//
//  Both tools are "tuning-aware": their fretboard reflects whatever instrument +
//  tuning the player chose in the Tuner (e.g. Drop D, or a saved custom like
//  DADGAD). The single source of truth is the app's shared `InstrumentSelectionStore`
//  — the SAME observable instance the Tuner writes to — consulted alongside the
//  player's saved `CustomTuningStore`. This struct encapsulates the "store →
//  instrument + active tuning" resolution so the two view models don't each carry
//  their own (previously identical) copy of it.
//
//  Previews/tests can construct it with no stores (falls back to standard guitar),
//  or pin an explicit instrument/tuning via the `fixed*` values.
//

import Foundation

@MainActor
struct InstrumentTuningContext {

    /// The app's shared selection memory (last-used instrument/tuning). `nil` in
    /// previews/tests → standard-guitar fallback.
    private let selection: InstrumentSelectionStore?
    /// The player's saved custom tunings, consulted when the recorded tuning name
    /// isn't a built-in preset.
    private let customTunings: CustomTuningStore?
    /// An explicitly pinned instrument/tuning (previews/tests), overriding the store.
    private let fixedInstrument: Instrument?
    private let fixedTuning: Tuning?

    init(
        selection: InstrumentSelectionStore? = nil,
        customTunings: CustomTuningStore? = nil,
        instrument: Instrument? = nil,
        currentTuning: Tuning? = nil
    ) {
        self.selection = selection
        self.customTunings = customTunings
        self.fixedInstrument = instrument
        self.fixedTuning = currentTuning
    }

    /// The instrument currently in effect — from the shared selection store, an
    /// explicitly pinned instrument, or the standard-guitar default.
    var currentInstrument: Instrument {
        fixedInstrument ?? selection?.restoredInstrument() ?? InstrumentLibrary.default
    }

    /// The instrument's STANDARD (home) tuning — what the `Current ⇄ Standard`
    /// override maps against. For a guitar this is EADGBE.
    var standardTuning: Tuning {
        currentInstrument.defaultTuning
            ?? Tuning(name: "Standard", category: .standard, strings: [])
    }

    /// The tuning the player is actually on (e.g. Drop D, or a saved custom like
    /// DADGAD), resolved from the shared selection — consulting built-in presets
    /// first and the player's saved custom tunings second. Falls back to a pinned
    /// tuning, then to standard.
    var currentTuning: Tuning {
        if let fixedTuning { return fixedTuning }
        guard let selection else { return standardTuning }
        let customs = customTunings?.tunings(forInstrumentID: currentInstrument.id) ?? []
        return selection.restoredTuning(for: currentInstrument, customTunings: customs)
    }
}
