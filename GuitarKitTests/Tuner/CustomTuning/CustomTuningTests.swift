//
//  CustomTuningTests.swift
//  GuitarKitTests
//
//  Tests for the custom-tuning pure helpers (auto-naming, out-of-range) and the
//  persistent store (save/round-trip/replace/delete via a throwaway suite).
//

import XCTest
@testable import GuitarKit

final class CustomTuningTests: XCTestCase {

    private func n(_ pc: PitchClass, _ oct: Int) -> Note { Note(pitchClass: pc, octave: oct) }

    // MARK: - Auto-suggested name

    func test_autoName_standardGuitar_isEADGBE() {
        let strings = [n(.e,2), n(.a,2), n(.d,3), n(.g,3), n(.b,3), n(.e,4)]
        XCTAssertEqual(CustomTuningSupport.autoSuggestedName(for: strings), "EADGBE")
    }

    func test_autoName_dadgad() {
        let strings = [n(.d,2), n(.a,2), n(.d,3), n(.g,3), n(.a,3), n(.d,4)]
        XCTAssertEqual(CustomTuningSupport.autoSuggestedName(for: strings), "DADGAD")
    }

    func test_autoName_empty_isCustom() {
        XCTAssertEqual(CustomTuningSupport.autoSuggestedName(for: []), "Custom")
    }

    // MARK: - Out of range (gentle, non-blocking)

    func test_inRange_dropD_notFlagged() {
        // Drop D lowers the 6th string a whole tone — well within an octave.
        let strings = [n(.d,2), n(.a,2), n(.d,3), n(.g,3), n(.b,3), n(.e,4)]
        XCTAssertFalse(CustomTuningSupport.isOutOfRange(strings: strings, for: InstrumentLibrary.guitar6))
    }

    func test_outOfRange_stringDroppedTwoOctaves_isFlagged() {
        // Low E pushed down two octaves (>12 semitones) → flagged.
        var strings = [n(.e,2), n(.a,2), n(.d,3), n(.g,3), n(.b,3), n(.e,4)]
        strings[0] = Note.from(midiNumber: n(.e,2).midiNumber - 24)
        let flagged = CustomTuningSupport.outOfRangeStringIndices(strings: strings, for: InstrumentLibrary.guitar6)
        XCTAssertEqual(flagged, [0])
        XCTAssertTrue(CustomTuningSupport.isOutOfRange(strings: strings, for: InstrumentLibrary.guitar6))
    }

    func test_exactlyOneOctave_notFlagged() {
        // Exactly 12 semitones is allowed (strict >).
        var strings = [n(.e,2), n(.a,2), n(.d,3), n(.g,3), n(.b,3), n(.e,4)]
        strings[0] = Note.from(midiNumber: n(.e,2).midiNumber - 12)
        XCTAssertFalse(CustomTuningSupport.isOutOfRange(strings: strings, for: InstrumentLibrary.guitar6))
    }

    // MARK: - Store

    private func makeStore() -> (CustomTuningStore, UserDefaults) {
        let suite = "guitarkit.tests.customtuning.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (CustomTuningStore(defaults: defaults), defaults)
    }

    private var dadgad: Tuning {
        Tuning(name: "DADGAD", category: .alternate,
               strings: [n(.d,2), n(.a,2), n(.d,3), n(.g,3), n(.a,3), n(.d,4)])
    }

    func test_store_savesAndRoundTrips() {
        let (store, defaults) = makeStore()
        store.save(dadgad, forInstrumentID: "guitar-6")

        // A fresh store reading the SAME suite sees the saved tuning (persisted).
        let reloaded = CustomTuningStore(defaults: defaults)
        let tunings = reloaded.tunings(forInstrumentID: "guitar-6")
        XCTAssertEqual(tunings.count, 1)
        XCTAssertEqual(tunings.first?.name, "DADGAD")
        XCTAssertEqual(tunings.first?.strings, dadgad.strings)
    }

    func test_store_saveSameName_replaces() {
        let (store, _) = makeStore()
        store.save(dadgad, forInstrumentID: "guitar-6")
        // Re-save under the same name with different strings → replaces, no dupe.
        let edited = Tuning(name: "DADGAD", category: .alternate,
                            strings: [n(.d,2), n(.a,2), n(.d,3), n(.g,3), n(.b,3), n(.d,4)])
        store.save(edited, forInstrumentID: "guitar-6")
        let tunings = store.tunings(forInstrumentID: "guitar-6")
        XCTAssertEqual(tunings.count, 1)
        XCTAssertEqual(tunings.first?.strings, edited.strings)
    }

    func test_store_delete() {
        let (store, _) = makeStore()
        store.save(dadgad, forInstrumentID: "guitar-6")
        store.delete(named: "DADGAD", forInstrumentID: "guitar-6")
        XCTAssertTrue(store.tunings(forInstrumentID: "guitar-6").isEmpty)
    }

    func test_store_isolatedPerInstrument() {
        let (store, _) = makeStore()
        store.save(dadgad, forInstrumentID: "guitar-6")
        XCTAssertTrue(store.tunings(forInstrumentID: "bass-4").isEmpty)
    }
}
