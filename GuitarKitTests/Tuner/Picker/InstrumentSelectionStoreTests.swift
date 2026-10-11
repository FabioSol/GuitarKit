//
//  InstrumentSelectionStoreTests.swift
//  GuitarKitTests
//
//  Behavioural tests for the tuner picker's persistent memory. We exercise the
//  store through its public surface: restoring the last instrument + tuning across
//  a "relaunch", recording selections (which both update last-used and increment
//  usage), the seeded-then-usage-driven Most-used ordering, and the fall-back to
//  the library default when nothing/unknown is stored.
//
//  Like SettingsStoreTests, every test runs against an ISOLATED `UserDefaults`
//  suite so we never read or pollute the developer's real preferences, and each
//  test starts from a clean slate (removePersistentDomain in setUp/tearDown).
//
//  `@MainActor` on the whole case: `InstrumentSelectionStore` is main-actor-
//  isolated, so its init and properties can only be touched from the main actor.
//

import XCTest
@testable import GuitarKit

@MainActor
final class InstrumentSelectionStoreTests: XCTestCase {

    /// A throwaway defaults store unique to this test case. A named suite is a
    /// separate plist from `.standard`, so it's safe to wipe between tests.
    private var defaults: UserDefaults!
    // Per-test-instance UUID so suites never collide under parallel execution.
    private let suiteName = "guitarkit.tests.picker.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        // Start clean in case a previous run left anything behind.
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Fresh install defaults

    func test_freshStore_hasNoLastSelection() {
        let store = InstrumentSelectionStore(defaults: defaults)
        XCTAssertNil(store.lastInstrumentID, "A fresh install has no last instrument.")
        XCTAssertNil(store.lastTuningName, "A fresh install has no last tuning.")
    }

    /// Restore falls back to the library default (standard guitar) when nothing is
    /// stored, and to that instrument's home tuning.
    func test_freshStore_restoresLibraryDefault() {
        let store = InstrumentSelectionStore(defaults: defaults)

        let instrument = store.restoredInstrument()
        XCTAssertEqual(instrument, InstrumentLibrary.default,
                       "With nothing stored, restore should give the cold-start default.")

        let tuning = store.restoredTuning(for: instrument)
        XCTAssertEqual(tuning, instrument.defaultTuning,
                       "With nothing stored, restore should give the instrument's home tuning.")
    }

    // MARK: - Persistence (round-trip)

    /// The core acceptance criterion: the last instrument + tuning survives a
    /// relaunch (a brand-new store reading the same suite sees them).
    func test_lastSelection_persistsAcrossNewStore() {
        let first = InstrumentSelectionStore(defaults: defaults)
        first.recordSelection(instrumentID: "bass-4", tuningName: "Drop D")

        let second = InstrumentSelectionStore(defaults: defaults)
        XCTAssertEqual(second.lastInstrumentID, "bass-4")
        XCTAssertEqual(second.lastTuningName, "Drop D")

        // And it resolves back to the real Bass + its Drop D preset.
        let instrument = second.restoredInstrument()
        XCTAssertEqual(instrument, InstrumentLibrary.bass4)
        XCTAssertEqual(second.restoredTuning(for: instrument).name, "Drop D")
    }

    /// Usage counts also persist across a relaunch.
    func test_usageCounts_persistAcrossNewStore() {
        let first = InstrumentSelectionStore(defaults: defaults)
        first.recordSelection(instrumentID: "bass-4", tuningName: "Standard")
        first.recordSelection(instrumentID: "bass-4", tuningName: "Standard")

        let second = InstrumentSelectionStore(defaults: defaults)
        XCTAssertEqual(second.usageCounts["bass-4"], 2,
                       "Usage counts should survive a relaunch.")
    }

    // MARK: - Recording a selection

    /// recordSelection increments the usage count for the chosen instrument.
    func test_recordSelection_incrementsUsage() {
        let store = InstrumentSelectionStore(defaults: defaults)
        XCTAssertNil(store.usageCounts["violin"])

        store.recordSelection(instrumentID: "violin", tuningName: "Standard")
        XCTAssertEqual(store.usageCounts["violin"], 1)

        store.recordSelection(instrumentID: "violin", tuningName: "Standard")
        XCTAssertEqual(store.usageCounts["violin"], 2)
    }

    // MARK: - Most-used ordering

    /// On a fresh install the Most-used group is non-empty (seeded) and leads with
    /// the cold-start default guitar.
    func test_mostUsed_isSeededOnFreshInstall() {
        let store = InstrumentSelectionStore(defaults: defaults)
        let ids = store.mostUsedInstrumentIDs(limit: 3)

        XCTAssertFalse(ids.isEmpty, "Most-used should be seeded (non-empty) on a fresh install.")
        XCTAssertEqual(ids.first, "guitar-6",
                       "The seeded order should lead with the cold-start default guitar.")
    }

    /// Real selections out-rank the seed: hammering an un-seeded (or low-seed)
    /// instrument bumps it to the top of the Most-used ordering — the seed "washes
    /// out".
    func test_mostUsed_realUsageBumpsOrdering() {
        let store = InstrumentSelectionStore(defaults: defaults)

        // Violin has NO seed prior. A few real selections should overtake the
        // seeded guitar (prior 3) and lead the list.
        for _ in 0..<5 {
            store.recordSelection(instrumentID: "violin", tuningName: "Standard")
        }

        let ids = store.mostUsedInstrumentIDs(limit: 3)
        XCTAssertEqual(ids.first, "violin",
                       "Heavy real use should out-rank the seeded priors (seed washes out).")
    }

    /// The `limit` is respected.
    func test_mostUsed_respectsLimit() {
        let store = InstrumentSelectionStore(defaults: defaults)
        // Seed alone gives 3 instruments; record more so several have scores.
        store.recordSelection(instrumentID: "violin", tuningName: "Standard")
        store.recordSelection(instrumentID: "guitar-7", tuningName: "Standard")

        let ids = store.mostUsedInstrumentIDs(limit: 2)
        XCTAssertEqual(ids.count, 2, "Most-used should cap at the requested limit.")
    }

    // MARK: - Restore fall-backs

    /// An unknown stored instrument id (e.g. removed in a later version) falls back
    /// to the library default rather than returning something broken.
    func test_restoredInstrument_unknownIDFallsBackToDefault() {
        let first = InstrumentSelectionStore(defaults: defaults)
        first.recordSelection(instrumentID: "nonexistent-instrument", tuningName: "Whatever")

        let second = InstrumentSelectionStore(defaults: defaults)
        XCTAssertEqual(second.restoredInstrument(), InstrumentLibrary.default,
                       "An unknown stored id should fall back to the library default.")
    }

    /// A stored tuning name that doesn't exist on the resolved instrument falls
    /// back to that instrument's home tuning.
    func test_restoredTuning_unknownNameFallsBackToHomeTuning() {
        let first = InstrumentSelectionStore(defaults: defaults)
        // Real instrument, but a tuning name guitar-6 doesn't have.
        first.recordSelection(instrumentID: "guitar-6", tuningName: "Not A Real Tuning")

        let second = InstrumentSelectionStore(defaults: defaults)
        let instrument = second.restoredInstrument()
        XCTAssertEqual(instrument, InstrumentLibrary.guitar6)
        XCTAssertEqual(second.restoredTuning(for: instrument), instrument.defaultTuning,
                       "An unmatched tuning name should fall back to the home tuning.")
    }

    /// A stored tuning name that DOES exist resolves to that exact preset.
    func test_restoredTuning_knownNameResolvesToPreset() {
        let first = InstrumentSelectionStore(defaults: defaults)
        first.recordSelection(instrumentID: "guitar-6", tuningName: "Open G")

        let second = InstrumentSelectionStore(defaults: defaults)
        let instrument = second.restoredInstrument()
        let tuning = second.restoredTuning(for: instrument)
        XCTAssertEqual(tuning.name, "Open G")
        XCTAssertEqual(tuning.category, .open)
    }
}
