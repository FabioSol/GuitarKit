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

    var body: some View {
        // `ZStack(alignment: .bottom)` layers the tool screen behind the nav,
        // pinning the nav to the bottom edge.
        ZStack(alignment: .bottom) {

            // THE TOOL SCREEN.
            // For this foundation slice every tool shows the shared
            // placeholder. We `switch` over the selection so later slices can
            // swap each case for the real screen (`TunerView()`, etc.) one at a
            // time. The `switch` is exhaustive, so the compiler will remind us
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
    }

    /// The screen for the currently selected tool. Pulled into a computed
    /// property (with `@ViewBuilder` so each `case` can return a different
    /// view type) to keep `body` tidy and make future per-tool swaps obvious.
    @ViewBuilder
    private var currentToolScreen: some View {
        switch selection {
        case .tuner:
            ToolPlaceholderView(tool: .tuner)
        case .metronome:
            ToolPlaceholderView(tool: .metronome)
        case .circleOfFifths:
            // The real Circle-of-Fifths explorer (slice #18) replaces the
            // placeholder. It owns its own `@State` view model, so its selection
            // is preserved while the app runs even as we navigate away and back.
            CircleOfFifthsView()
        case .chords:
            ToolPlaceholderView(tool: .chords)
        case .scales:
            ToolPlaceholderView(tool: .scales)
        }
    }
}

#Preview {
    RootView()
}
