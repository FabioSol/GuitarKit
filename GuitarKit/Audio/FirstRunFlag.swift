//
//  FirstRunFlag.swift
//  GuitarKit
//
//  A tiny persisted boolean answering "have we shown the first-run mic priming
//  screen yet?" Wrapped in its own type so:
//    • the UserDefaults key lives in exactly one place (no stringly-typed typos
//      scattered around), and
//    • we can inject a throwaway `UserDefaults` in tests and assert the
//      "first launch then never again" behavior without polluting real prefs.
//

import Foundation

/// Remembers, across launches, whether the user has already seen the priming
/// screen. Backed by `UserDefaults` (the small, on-device key/value store iOS
/// gives every app for simple preferences — exactly the right tool for a single
/// flag; no database needed).
struct FirstRunFlag {

    /// The single source of truth for the key string. `private static` so it
    /// can't be mistyped elsewhere.
    private static let key = "guitarkit.hasCompletedFirstRunPriming"

    /// Which defaults store to use. Defaults to `.standard` (the app's normal
    /// store) in production; tests pass a fresh, isolated suite.
    ///
    /// WHY INJECT IT?
    /// Hard-coding `UserDefaults.standard` inside the methods would make this
    /// untestable (tests would read/write the developer's real defaults). Taking
    /// the store as a stored property is lightweight dependency injection.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `true` once the user has been shown (and dismissed) the priming screen.
    ///
    /// NOTE: `UserDefaults.bool(forKey:)` returns `false` for a missing key,
    /// which is exactly what we want — an untouched install reads `false`
    /// (= "first run, show priming").
    var hasCompletedPriming: Bool {
        defaults.bool(forKey: Self.key)
    }

    /// Record that priming is done so every future launch skips straight to the
    /// Tuner. Idempotent — calling it twice is harmless.
    func markPrimingComplete() {
        defaults.set(true, forKey: Self.key)
    }
}
