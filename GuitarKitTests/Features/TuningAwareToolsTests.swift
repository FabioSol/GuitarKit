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
