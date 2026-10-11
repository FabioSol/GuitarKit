//
//  InstrumentTuningContext.swift
//  GuitarKit — shared tool support
//
//  The tuning-derivation the Chords and Scales tools BOTH need, in one place.
//
//  Both tools are "tuning-aware": their fretboard reflects whatever instrument +
//  tuning the player chose in the Tuner (e.g. Drop D, or a saved custom like
//  DADGAD). The single source of truth is the app's shared `InstrumentSelectionStore`
//  — the SAME observable instance the Tuner writes to (through
//  `TunerCoordinator.select`), which resolves custom tunings itself. This struct
//  adds only what previews/tests need on top: pinning a fixed instrument/tuning.
//
//  Previews/tests can construct it with no stores (falls back to standard guitar),
//  or pin an explicit instrument/tuning via the `fixed*` values.
//

import Foundation

@MainActor
struct InstrumentTuningContext {

    /// The app's shared selection (which resolves custom tunings itself).
    /// `nil` in previews/tests → standard-guitar fallback.
    private let selection: InstrumentSelectionStore?
    /// An explicitly pinned instrument/tuning (previews/tests), overriding the store.
    private let fixedInstrument: Instrument?
    private let fixedTuning: Tuning?

    init(
        selection: InstrumentSelectionStore? = nil,
        instrument: Instrument? = nil,
        currentTuning: Tuning? = nil
    ) {
        self.selection = selection
        self.fixedInstrument = instrument
        self.fixedTuning = currentTuning
    }

    /// The instrument currently in effect — pinned, or the shared selection's,
    /// or the standard-guitar default.
    var currentInstrument: Instrument {
        fixedInstrument ?? selection?.currentInstrument ?? InstrumentLibrary.default
    }

    /// The instrument's STANDARD (home) tuning — what the `Current ⇄ Standard`
    /// override maps against. For a guitar this is EADGBE.
    var standardTuning: Tuning {
        currentInstrument.defaultTuning
            ?? Tuning(name: "Standard", category: .standard, strings: [])
    }

    /// The tuning the player is actually on (e.g. Drop D, or a saved custom
    /// like DADGAD) — pinned, or the shared selection's, or standard.
    var currentTuning: Tuning {
        fixedTuning ?? selection?.currentTuning ?? standardTuning
    }
}
