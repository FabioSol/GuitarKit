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

    /// The player's instrument + tuning selection, OWNED here at the shell so it's
    /// the single shared source of truth across tools. The Tuner writes to it (when
    /// the player picks an instrument/tuning), and the tuning-aware Chords/Scales
    /// tools read from it — so tuning the guitar to Drop D in the Tuner is reflected
    /// in their voicings/scale shapes. Injected into the environment for the Tuner.
    /// Seeded in `init` (shared with the Chords/Scales models).
    @State private var instrumentSelection: InstrumentSelectionStore

    /// The player's saved CUSTOM tunings, also owned at the shell so the Tuner and
    /// the tuning-aware Chords/Scales tools resolve the same customs. Seeded in
    /// `init` and injected into the environment for the Tuner.
    @State private var customTunings: CustomTuningStore

    // The view models for the harmony tools, OWNED here at the shell so they
    // outlive the per-tool screens (which `.id(selection)` recreates on each
    // switch). Hoisting them up here is what lets two things work at once
    // (slice #21): each tool's state is PRESERVED when you navigate away and
    // back, and the Circle's cross-links can LOAD context into Chords/Scales
    // before those screens appear. Chords/Scales also receive the shared
    // `instrumentSelection` so they stay tuning-aware (see `init`).
    @State private var circleModel = CircleOfFifthsViewModel()
    @State private var chordsModel: ChordsViewModel
    @State private var scalesModel: ScalesViewModel
    // The Metronome's model is hoisted here too so its tempo / time signature /
    // accents survive navigating away and back (its view is rebuilt by the
    // `switch` like the others). Audio still stops on leave via `onDisappear`.
    @State private var metronomeModel = MetronomeViewModel()

    /// Build the shell, wiring ONE shared `InstrumentSelectionStore` into both the
    /// environment (for the Tuner) and the Chords/Scales view models, so all three
    /// tools agree on the current instrument + tuning. We construct the store here
    /// and seed each `@State` from it; because it's a reference type, every tool
    /// holds the same instance and sees the same live updates.
    init() {
        let selection = InstrumentSelectionStore()
        let customs = CustomTuningStore()
        _instrumentSelection = State(initialValue: selection)
        _customTunings = State(initialValue: customs)
        _chordsModel = State(initialValue: ChordsViewModel(selection: selection, customTunings: customs))
        _scalesModel = State(initialValue: ScalesViewModel(selection: selection, customTunings: customs))
    }

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
        // Share the instrument/tuning selection + custom tunings with the Tuner
        // (the Chords/Scales models already hold the same instances from `init`).
        .environment(instrumentSelection)
        .environment(customTunings)
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
            // The Metronome tool: a circular tempo dial driving the drift-free
            // `MetronomeEngine`. Its model is owned by the shell (above) so the
            // tempo/time-signature/accents survive navigating away and back.
            MetronomeView(model: metronomeModel)
        case .circleOfFifths:
            // The Circle-of-Fifths explorer (slice #18), now a HUB (slice #21):
            // its details panel cross-links into Chords and Scales. The model is
            // owned by the shell so the selection survives navigation.
            CircleOfFifthsView(
                viewModel: circleModel,
                onOpenChord: openChordInChordsTool,
                onOpenScale: openScaleInScalesTool
            )
        case .chords:
            // The Chords tool (slice #20): pick a root + quality and see a
            // playable voicing for the active tuning, built on the same pure
            // `Fretboard` engine the Scales tool uses.
            ChordsView(model: chordsModel)
        case .scales:
            // The Scales tool (slice #19): tuning-aware fretboard + scale shapes.
            ScalesView(model: scalesModel)
        }
    }

    // MARK: - Cross-links (slice #21)

    /// Load a chord into the Chords tool and switch the rotary nav to it. Because
    /// the Chords model is OWNED here, setting it before changing `selection`
    /// means the Chords screen appears already showing this chord — and returning
    /// to the Circle afterwards finds it unchanged (its model is owned here too).
    private func openChordInChordsTool(_ chord: Chord) {
        chordsModel.root = chord.root
        chordsModel.quality = chord.quality
        chordsModel.resetVoicing()      // land on the default shape, not mid-cycle
        withAnimation(.easeInOut(duration: 0.25)) { selection = .chords }
    }

    /// Load a scale into the Scales tool and switch the rotary nav to it.
    private func openScaleInScalesTool(_ scale: Scale) {
        scalesModel.root = scale.root
        scalesModel.scaleType = scale.type
        withAnimation(.easeInOut(duration: 0.25)) { selection = .scales }
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
