//
//  TuningAwareToolsTests.swift
//  GuitarKitTests
//
//  Regression coverage for the Chords/Scales tools following the player's chosen
//  tuning. Previously their view models captured a fixed `currentTuning` at init
//  (always standard), so tuning to Drop D in the Tuner never reached them and the
//  `Current ⇄ Standard` override did nothing. They now derive the tuning from the
//  shared `InstrumentSelectionStore` the Tuner writes to.
//

import XCTest
@testable import GuitarKit

@MainActor
final class TuningAwareToolsTests: XCTestCase {

    /// A fresh selection store on a throwaway suite, with `instrumentID` + `tuning`
    /// already recorded (as the Tuner's picker would on selection).
    private func store(recording instrumentID: String, _ tuningName: String) -> InstrumentSelectionStore {
        let suite = "guitarkit.tests.tuningaware.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = InstrumentSelectionStore(defaults: defaults)
        store.recordSelection(instrumentID: instrumentID, tuningName: tuningName)
        return store
    }

    /// A fresh custom-tuning store on a throwaway suite, optionally pre-seeded with
    /// `tuning` for `instrumentID`.
    private func customStore(saving tuning: Tuning? = nil, forInstrumentID instrumentID: String = "guitar-6") -> CustomTuningStore {
        let suite = "guitarkit.tests.tuningaware.custom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = CustomTuningStore(defaults: defaults)
        if let tuning { store.save(tuning, forInstrumentID: instrumentID) }
        return store
    }

    private func note(_ pc: PitchClass, _ oct: Int) -> Note { Note(pitchClass: pc, octave: oct) }

    /// DADGAD — a popular custom/alternate tuning whose low string is a D.
    private var dadgad: Tuning {
        Tuning(name: "DADGAD", category: .alternate,
               strings: [note(.d,2), note(.a,2), note(.d,3), note(.g,3), note(.a,3), note(.d,4)])
    }

    // MARK: - Chords

    func test_chords_followSelectedTuning_dropD() {
        let model = ChordsViewModel(selection: store(recording: "guitar-6", "Drop D"))

        XCTAssertEqual(model.currentTuning.name, "Drop D",
            "Chords should reflect the tuning chosen in the Tuner")
        // The low string should now be a D (Drop D), not the standard low E.
        XCTAssertEqual(model.currentTuning.strings.first?.pitchClass, .d)
        // And it must DIFFER from the instrument's standard tuning…
        XCTAssertEqual(model.standardTuning.strings.first?.pitchClass, .e)
        XCTAssertNotEqual(model.currentTuning.strings, model.standardTuning.strings)
    }

    func test_chords_standardOverride_switchesBackToStandard() {
        let model = ChordsViewModel(selection: store(recording: "guitar-6", "Drop D"))

        // Off → the active board is the chosen Drop D.
        XCTAssertEqual(model.activeTuning.strings.first?.pitchClass, .d)
        // On → the override maps against the instrument's standard tuning.
        model.useStandardOverride = true
        XCTAssertEqual(model.activeTuning.strings.first?.pitchClass, .e)
        XCTAssertEqual(model.activeTuning.strings, model.standardTuning.strings)
    }

    // MARK: - Custom tunings

    func test_chords_followSavedCustomTuning_dadgad() {
        // The player saved DADGAD and selected it; its name is recorded but it is
        // NOT a built-in preset, so it must be resolved via the custom store.
        let model = ChordsViewModel(
            selection: store(recording: "guitar-6", "DADGAD"),
            customTunings: customStore(saving: dadgad)
        )

        XCTAssertEqual(model.currentTuning.name, "DADGAD",
            "Chords should resolve a saved CUSTOM tuning, not just built-in presets")
        XCTAssertEqual(model.currentTuning.strings, dadgad.strings)
        // High string drops to D in DADGAD, unlike standard's high E.
        XCTAssertEqual(model.currentTuning.strings.last?.pitchClass, .d)
        XCTAssertEqual(model.standardTuning.strings.last?.pitchClass, .e)
    }

    func test_scales_followSavedCustomTuning_dadgad() {
        let model = ScalesViewModel(
            selection: store(recording: "guitar-6", "DADGAD"),
            customTunings: customStore(saving: dadgad)
        )
        XCTAssertEqual(model.currentTuning.strings, dadgad.strings)
    }

    func test_presetWinsOverCustomOfSameName() {
        // A preset and a custom share the name "Drop D": the built-in preset wins.
        let model = ChordsViewModel(
            selection: store(recording: "guitar-6", "Drop D"),
            customTunings: customStore(saving: Tuning(name: "Drop D", category: .alternate,
                strings: [note(.c,2), note(.a,2), note(.d,3), note(.g,3), note(.b,3), note(.e,4)]))
        )
        // Built-in Drop D's low string is D2; if the custom (low C) had won it'd be C.
        XCTAssertEqual(model.currentTuning.strings.first, note(.d, 2))
    }

    // MARK: - Scales

    func test_scales_followSelectedTuning_dropD() {
        let model = ScalesViewModel(selection: store(recording: "guitar-6", "Drop D"))

        XCTAssertEqual(model.currentTuning.name, "Drop D")
        XCTAssertEqual(model.activeTuning.strings.first?.pitchClass, .d)

        model.useStandardOverride = true
        XCTAssertEqual(model.activeTuning.strings.first?.pitchClass, .e)
    }

    // MARK: - No store (previews/tests) falls back to standard

    func test_noStore_fallsBackToStandardGuitar() {
        let chords = ChordsViewModel()
        XCTAssertEqual(chords.currentTuning.strings.first?.pitchClass, .e)
        // With no chosen tuning, current and standard agree (override is a no-op).
        XCTAssertEqual(chords.currentTuning.strings, chords.standardTuning.strings)
    }
}
