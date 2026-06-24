//
//  RootView.swift
//  GuitarKit
//
//  The app shell. It owns which tool is selected, shows that tool's screen,
//  and overlays the rotary navigation at the bottom.
//
//  KEY REQUIREMENT: the app launches STRAIGHT INTO THE TUNER — there is no
//  hub/home screen. We achieve that simply by initializing the selection to
//  `.tuner`.
//

import SwiftUI

struct RootView: View {

    /// The single piece of app-shell state: which tool is on screen. This view
    /// OWNS it (`@State`), and hands a two-way `$selection` binding down to the
    /// nav so taps can change it. It starts on `.tuner` → tuner-first launch.
    @State private var selection: GKTool = .tuner

    /// The app's global preferences, owned here at the shell so they live for the
    /// whole app lifetime. We inject them into the environment so any tool (e.g.
    /// the Tuner) can read them, and present the Settings screen from the gear.
    @State private var settings = SettingsStore()

    /// Whether the Settings sheet is showing.
    @State private var showingSettings = false

    var body: some View {
        // `ZStack(alignment: .bottom)` layers the tool screen behind the nav,
        // pinning the nav to the bottom edge.
        ZStack(alignment: .bottom) {

            // THE TOOL SCREEN.
            // We `switch` over the selection so each tool can show its real
            // screen. The `switch` is exhaustive, so the compiler will remind us
            // if we ever add a tool and forget to give it a screen.
            currentToolScreen
                // A cross-fade when the selected tool changes keeps screen
                // swaps gentle. `.animation(_:value:)` animates whenever
                // `selection` changes.
                .transition(.opacity)
                .id(selection) // give each tool its own identity so the
                               // transition actually runs on change.
                .animation(.easeInOut(duration: 0.25), value: selection)

            // THE ROTARY NAVIGATION, floating over the screen at the bottom.
            RotaryNavBar(selection: $selection)
                // Nudge it down a touch into the home-indicator area; the arc
                // reaches up into the content.
                .padding(.bottom, 4)
        }
        // The Settings gear, floating in the top-trailing corner above the tool.
        .overlay(alignment: .topTrailing) { settingsButton }
        // Make the global preferences available to every tool below us.
        .environment(settings)
        // Force the user's chosen appearance (or follow the system when `.system`).
        .preferredColorScheme(settings.theme.colorScheme)
        // Present Settings as a sheet wrapped in its own navigation container.
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(store: settings)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
    }

    /// The corner gear button that opens Settings.
    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(GKColor.textSecondary)
                .padding(12)
        }
        .accessibilityLabel("Settings")
        .padding(.top, 8)
        .padding(.trailing, 4)
    }

    /// The screen for the currently selected tool. Pulled into a computed
    /// property (with `@ViewBuilder` so each `case` can return a different
    /// view type) to keep `body` tidy and make future per-tool swaps obvious.
    @ViewBuilder
    private var currentToolScreen: some View {
        switch selection {
        case .tuner:
            // The Tuner is the first real tool. It owns mic priming, permission,
            // audio capture, and (for now) a live input-level meter. Other tools
            // still show the shared placeholder until their slices land.
            TunerView()
        case .metronome:
            // The Metronome tool (slice #15): a circular tempo dial driving the
            // drift-free `MetronomeEngine` from slice #14. It owns its own
            // `@State` view model so the tempo survives navigating away and back.
            MetronomeView()
        case .circleOfFifths:
            // The real Circle-of-Fifths explorer (slice #18) replaces the
            // placeholder. It owns its own `@State` view model, so its selection
            // is preserved while the app runs even as we navigate away and back.
            CircleOfFifthsView()
        case .chords:
            // The Chords tool (slice #20): pick a root + quality and see a
            // playable voicing for the active tuning, built on the same pure
            // `Fretboard` engine the Scales tool uses.
            ChordsView()
        case .scales:
            // The Scales tool (slice #19): tuning-aware fretboard + scale shapes.
            ScalesView()
        }
    }
}

// MARK: - Theme → ColorScheme

private extension AppTheme {
    /// Map the persisted theme to SwiftUI's optional `ColorScheme`, which is what
    /// `.preferredColorScheme` wants: `.system` follows the device (`nil`), while
    /// `.light`/`.dark` force their scheme.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

#Preview {
    RootView()
}
