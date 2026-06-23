//
//  FirstRunFlagTests.swift
//  GuitarKitTests
//
//  Tests the "show priming once, then never again" persistence rule. We inject
//  an isolated `UserDefaults` suite so we never read or pollute the real app
//  defaults, and we can start each test from a clean slate.
//

import XCTest
@testable import GuitarKit

final class FirstRunFlagTests: XCTestCase {

    /// A throwaway defaults store unique to each test run. Created in `setUp`,
    /// wiped in `tearDown` so tests don't leak state into one another.
    private var defaults: UserDefaults!
    private let suiteName = "guitarkit.tests.firstrun"

    override func setUp() {
        super.setUp()
        // A named suite is a separate plist from `.standard`. Perfect for tests.
        defaults = UserDefaults(suiteName: suiteName)
        // Start clean in case a previous run left anything behind.
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_freshInstall_hasNotCompletedPriming() {
        let flag = FirstRunFlag(defaults: defaults)
        XCTAssertFalse(flag.hasCompletedPriming,
                       "A brand-new install should report priming as not yet done.")
    }

    func test_markingComplete_persistsTrue() {
        let flag = FirstRunFlag(defaults: defaults)
        flag.markPrimingComplete()
        XCTAssertTrue(flag.hasCompletedPriming)
    }

    func test_completion_survivesAcrossNewInstances() {
        // Simulate two app launches sharing the same store: a second instance
        // (new launch) must see the flag the first one set.
        FirstRunFlag(defaults: defaults).markPrimingComplete()
        let nextLaunch = FirstRunFlag(defaults: defaults)
        XCTAssertTrue(nextLaunch.hasCompletedPriming,
                      "Priming completion must persist across launches.")
    }

    func test_markingComplete_isIdempotent() {
        let flag = FirstRunFlag(defaults: defaults)
        flag.markPrimingComplete()
        flag.markPrimingComplete()
        XCTAssertTrue(flag.hasCompletedPriming)
    }
}
