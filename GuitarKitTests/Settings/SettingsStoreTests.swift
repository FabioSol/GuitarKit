//
//  SettingsStoreTests.swift
//  GuitarKitTests
//
//  Behavioural tests for the global preferences store. We exercise it through its
//  public surface: defaults, persistence across "launches", reference-pitch
//  clamping, and reset. Like FirstRunFlagTests, every test runs against an
//  ISOLATED `UserDefaults` suite so we never read or pollute the developer's real
//  preferences, and each test starts from a clean slate.
//
//  `@MainActor` on the whole test case: `SettingsStore` is main-actor-isolated, so
//  its initialiser and properties can only be touched from the main actor. Marking
//  the test case `@MainActor` lets every test method call into it directly.
//

import XCTest
@testable import GuitarKit

@MainActor
final class SettingsStoreTests: XCTestCase {

    /// A throwaway defaults store unique to this test case. A named suite is a
    /// separate plist from `.standard`, so it's safe to wipe.
    private var defaults: UserDefaults!
    private let suiteName = "guitarkit.tests.settings"

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

    // MARK: - Defaults

    func test_freshStore_hasCorrectDefaults() {
        let store = SettingsStore(defaults: defaults)

        // Tuning
        XCTAssertEqual(store.referencePitchHz, 440, "Reference pitch should default to concert 440 Hz.")
        XCTAssertFalse(store.sweetenedTuningEnabled)
        XCTAssertEqual(store.inTuneSensitivity, .standard)

        // Feedback — the two PRD-critical defaults: haptics ON, sound OFF.
        XCTAssertTrue(store.hapticsEnabled, "Haptics should be ON by default.")
        XCTAssertFalse(store.soundEnabled, "Sound should be OFF by default (silent by default).")
        XCTAssertEqual(store.confirmationSound, .chime)

        // Appearance
        XCTAssertEqual(store.theme, .system)
        XCTAssertEqual(store.accent, .purple)

        // Instrument
        XCTAssertEqual(store.handedness, .right)
        XCTAssertEqual(store.defaultLabeling, .sharps)

        // Advanced flags
        XCTAssertFalse(store.experimentalHeroVisualization)
        XCTAssertFalse(store.experimentalFingerNumberLabels)
        XCTAssertFalse(store.experimentalReactiveBackdrop)
    }

    // MARK: - Persistence (round-trip)

    func test_writtenValues_persistAcrossNewStore() {
        // First "launch": change several settings.
        let first = SettingsStore(defaults: defaults)
        first.referencePitchHz = 442
        first.hapticsEnabled = false
        first.soundEnabled = true
        first.confirmationSound = .pluck
        first.theme = .dark
        first.handedness = .left
        first.defaultLabeling = .flats
        first.inTuneSensitivity = .strict
        first.sweetenedTuningEnabled = true
        first.experimentalHeroVisualization = true

        // Second "launch": a brand-new store reading the SAME suite must see them.
        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.referencePitchHz, 442)
        XCTAssertFalse(second.hapticsEnabled)
        XCTAssertTrue(second.soundEnabled)
        XCTAssertEqual(second.confirmationSound, .pluck)
        XCTAssertEqual(second.theme, .dark)
        XCTAssertEqual(second.handedness, .left)
        XCTAssertEqual(second.defaultLabeling, .flats)
        XCTAssertEqual(second.inTuneSensitivity, .strict)
        XCTAssertTrue(second.sweetenedTuningEnabled)
        XCTAssertTrue(second.experimentalHeroVisualization)
    }

    /// A subtle but important case: a `true`-default Bool (haptics) set to `false`
    /// must persist as `false`, not silently fall back to the `true` default. This
    /// guards the `object(forKey:)`-vs-`bool(forKey:)` distinction in the store.
    func test_trueDefaultBool_persistsFalse() {
        let first = SettingsStore(defaults: defaults)
        first.hapticsEnabled = false

        let second = SettingsStore(defaults: defaults)
        XCTAssertFalse(second.hapticsEnabled,
                       "Turning OFF a setting that defaults ON must survive a relaunch.")
    }

    // MARK: - Reference-pitch clamping

    func test_referencePitch_clampsBelowMinimum() {
        let store = SettingsStore(defaults: defaults)
        store.referencePitchHz = 300 // below the 415 floor
        XCTAssertEqual(store.referencePitchHz, ReferencePitch.minHz)
    }

    func test_referencePitch_clampsAboveMaximum() {
        let store = SettingsStore(defaults: defaults)
        store.referencePitchHz = 9000 // above the 466 ceiling
        XCTAssertEqual(store.referencePitchHz, ReferencePitch.maxHz)
    }

    func test_referencePitch_clampedValuePersists() {
        // An out-of-range write should persist the CLAMPED value, not the raw one.
        let first = SettingsStore(defaults: defaults)
        first.referencePitchHz = 9000

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.referencePitchHz, ReferencePitch.maxHz)
    }

    // MARK: - Reset

    func test_reset_restoresDefaults() {
        let store = SettingsStore(defaults: defaults)
        // Move everything away from its default.
        store.referencePitchHz = 432
        store.hapticsEnabled = false
        store.soundEnabled = true
        store.theme = .light
        store.handedness = .left
        store.defaultLabeling = .flats
        store.inTuneSensitivity = .relaxed
        store.sweetenedTuningEnabled = true
        store.experimentalHeroVisualization = true

        store.reset()

        XCTAssertEqual(store.referencePitchHz, 440)
        XCTAssertTrue(store.hapticsEnabled)
        XCTAssertFalse(store.soundEnabled)
        XCTAssertEqual(store.theme, .system)
        XCTAssertEqual(store.handedness, .right)
        XCTAssertEqual(store.defaultLabeling, .sharps)
        XCTAssertEqual(store.inTuneSensitivity, .standard)
        XCTAssertFalse(store.sweetenedTuningEnabled)
        XCTAssertFalse(store.experimentalHeroVisualization)
    }

    /// Reset must also PERSIST the defaults, so a relaunch after reset is clean.
    func test_reset_persists() {
        let first = SettingsStore(defaults: defaults)
        first.hapticsEnabled = false
        first.theme = .dark
        first.reset()

        let second = SettingsStore(defaults: defaults)
        XCTAssertTrue(second.hapticsEnabled)
        XCTAssertEqual(second.theme, .system)
    }
}
