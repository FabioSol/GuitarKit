//
//  GuitarKitApp.swift
//  GuitarKit
//
//  The app's entry point.
//

import SwiftUI

// `@main` marks the single type that owns the program's launch. A type
// conforming to the `App` protocol describes the app's scenes (its windows).
@main
struct GuitarKitApp: App {

    // `body` returns the app's scenes. `some Scene` means "some concrete Scene
    // type, hidden" — the SwiftUI analogue of `some View` but at the app level.
    var body: some Scene {
        // `WindowGroup` is the standard scene for an app with a main window.
        WindowGroup {
            // Launch straight into the app shell, which itself opens on the
            // Tuner — no hub/home screen.
            RootView()
                // DARK-FIRST: we *prefer* dark mode as the default look, while
                // still fully supporting light mode (the design tokens adapt to
                // both). `.preferredColorScheme(.dark)` sets the default; if a
                // user explicitly forces light at the system level, our colors
                // still resolve correctly because they're appearance-aware.
                .preferredColorScheme(.dark)
        }
    }
}
