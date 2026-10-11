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

    /// The player's instrument + tuning selection (which also owns their saved
    /// custom tunings), OWNED here at the shell so it's the single source of
    /// truth across tools. The Tuner changes it — only through
    /// `TunerCoordinator.select` — and the tuning-aware Chords/Scales tools read
    /// it, so tuning to Drop D in the Tuner reshapes their voicings and scales.
    /// Seeded in `init` and handed to the coordinator and the Chords/Scales models.
    @State private var instrumentSelection: InstrumentSelectionStore

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
    // The Tuner's audio brain, hoisted like the models above: rebuilt with the
    // screen it would lose the tuning session (strings already latched) and
    // pay for a fresh audio engine on every return to the Tuner. The Tuner
    // screen stops the mic when it leaves and restarts it when it comes back.
    @State private var tunerCoordinator: TunerCoordinator

    /// Set to `true` while the Tuner is showing its first-run priming screen.
    /// Driven by `TunerPrimingKey` so the nav bar and settings button hide
    /// themselves — they don't make sense on that screen and overlap the button.
    @State private var tunerIsPriming = false

    /// Whether the metronome mini-player is visible. Becomes `true` when the
    /// metronome starts while the user is on another tool (or when they navigate
    /// away while it's playing). Only cleared by the explicit stop button — the
    /// control stays on screen while paused so the user can resume or fully stop.
    @State private var showMetronomeMini = false

    /// Build the shell, wiring ONE shared `InstrumentSelectionStore` (with the
    /// custom tunings inside it) into the Tuner's coordinator and the
    /// Chords/Scales view models, so all three tools agree on the current
    /// instrument + tuning. It's a reference type, so every tool holds the same
    /// instance and sees the same live updates.
    init() {
        let customs = CustomTuningStore()
        let selection = InstrumentSelectionStore(customTunings: customs)
        _instrumentSelection = State(initialValue: selection)
        _chordsModel = State(initialValue: ChordsViewModel(selection: selection))
        _scalesModel = State(initialValue: ScalesViewModel(selection: selection))
        _tunerCoordinator = State(initialValue: TunerCoordinator(selection: selection))
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
                // TunerView bubbles this up when showing its first-run priming
                // screen so we can hide the chrome that doesn't belong there.
                .onPreferenceChange(TunerPrimingKey.self) { tunerIsPriming = $0 }

            // THE ROTARY NAVIGATION, floating over the screen at the bottom.
            // Hidden while the Tuner's priming screen is up — it overlaps the
            // call-to-action button and makes no sense before the mic is set up.
            if !tunerIsPriming {
                RotaryNavBar(selection: $selection)
                    .padding(.bottom, 4)
            }
        }
        // SWIPE NAVIGATION — using `.gesture` (not `.highPriorityGesture`) so
        // child views keep priority. A horizontal ScrollView (e.g. the Scales
        // fretboard) captures its own touches first; this fires only when no
        // child gesture claims the drag. Non-wrapping: stops at first/last tool.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy), abs(dx) > 60 else { return }
                    if dx < 0 { navigateForward() } else { navigateBackward() }
                }
        )
        // The Settings gear, floating in the top-trailing corner above the tool.
        .overlay(alignment: .topTrailing) {
            if !tunerIsPriming { settingsButton }
        }
        // Metronome mini-player, top-left, visible while away from the metronome.
        .overlay(alignment: .topLeading) {
            if showMetronomeMini && selection != .metronome {
                MetronomeMiniPlayerView(
                    isPlaying: metronomeModel.isPlaying,
                    onToggle: metronomeModel.toggle,
                    onStop: {
                        metronomeModel.stop()
                        showMetronomeMini = false
                    }
                )
                .padding(.top, 52)
                .padding(.leading, 12)
                .transition(.scale(scale: 0.7, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showMetronomeMini)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: metronomeModel.isPlaying)
        // Show the mini-player when the metronome starts while on another tool,
        // or when the user navigates away while it's already playing.
        .onChange(of: metronomeModel.isPlaying) { _, playing in
            if playing, selection != .metronome { showMetronomeMini = true }
        }
        .onChange(of: selection) { _, newSelection in
            if newSelection == .metronome {
                showMetronomeMini = false
            } else if metronomeModel.isPlaying {
                showMetronomeMini = true
            }
        }
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
            TunerView(coordinator: tunerCoordinator)
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

    // MARK: - Swipe navigation

    private func navigateForward() {
        let tools = GKTool.allCases
        guard let idx = tools.firstIndex(of: selection), idx < tools.count - 1 else { return }
        selection = tools[tools.index(after: idx)]
    }

    private func navigateBackward() {
        let tools = GKTool.allCases
        guard let idx = tools.firstIndex(of: selection), idx > 0 else { return }
        selection = tools[tools.index(before: idx)]
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
