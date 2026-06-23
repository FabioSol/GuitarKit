//
//  TunerView.swift
//  GuitarKit
//
//  The Tuner tab's top-level screen and the orchestrator for this slice. It
//  decides, based on first-run state + mic permission, WHICH sub-screen to show:
//
//      first launch & undetermined  → MicPrimingView   (value screen → prompt)
//      granted                      → live level meter  (audio flows!)
//      denied                       → MicDeniedView     (recoverable, → Settings)
//
//  Later slices replace the "granted" content (the meter) with the real tuner
//  hero, but the permission/lifecycle scaffolding here stays.
//

import SwiftUI

struct TunerView: View {

    // MARK: Owned state
    //
    // `@State` for reference types uses the `@Observable` macro under the hood:
    // SwiftUI keeps these alive for the view's lifetime and re-renders when
    // their observed properties change. This view OWNS the permission model and
    // the audio engine.

    /// The microphone-permission model. Drives which sub-screen we show.
    @State private var permission = MicrophonePermission()

    /// The audio capture engine. Its `level` feeds the meter and its raw buffers
    /// feed the pitch detector below.
    @State private var engine = AudioInputEngine()

    /// The pitch detector. We attach it to the engine's buffer stream so it sees
    /// the same audio, then feed its readings into the tuning session below.
    @State private var detector = MPMPitchDetector()

    /// The targeted tuning session. Each detector reading is fed in, and it drives
    /// the per-string in-tune logic the UI renders.
    @State private var session = TuningSessionModel()

    /// The tone generator (tap a peg in tone-mode to hear its target pitch) and
    /// the session coordinator that flips record↔playback around it.
    @State private var toneGenerator = ToneGenerator()
    @State private var coordinator = AudioSessionCoordinator()

    /// Whether the headstock is in tone-mode. In tone-mode detection is paused
    /// (mic off, session → playback) and tapping a peg plays instead of locks.
    @State private var isToneMode = false

    /// The picker's persistent memory (last-used instrument/tuning + usage counts)
    /// and whether the picker sheet is showing.
    @State private var selection = InstrumentSelectionStore()
    @State private var showingPicker = false

    /// Whether the user has already seen the first-run priming screen. We read
    /// the persisted flag once into view state, then flip it when priming
    /// completes. A plain `Bool` (not the struct) so SwiftUI re-renders on change.
    @State private var hasCompletedPriming = FirstRunFlag().hasCompletedPriming

    /// `scenePhase` tells us when the app moves between active/inactive/background.
    /// We watch it so that when the user returns from the Settings app (where
    /// they may have just granted the mic) we re-check permission and start audio.
    @Environment(\.scenePhase) private var scenePhase

    /// The global preferences, supplied by the app shell. Declared OPTIONAL so the
    /// view still works in previews where no store is injected — we just fall back
    /// to defaults. When present, reference pitch / sensitivity / haptics flow into
    /// the tuning session.
    @Environment(SettingsStore.self) private var settings: SettingsStore?

    // MARK: Body

    var body: some View {
        // Choose the sub-screen. `Group` lets us `switch`/`if` and still attach
        // shared modifiers (`.onChange`, `.task`) to the whole thing.
        Group {
            if shouldShowPriming {
                // FIRST RUN: explain value, then (on Start) request permission.
                MicPrimingView(onStart: handleStartTapped)
            } else {
                switch permission.state {
                case .undetermined:
                    // Returning user who somehow never decided (rare). Show the
                    // priming screen's CTA path again rather than a blank meter.
                    MicPrimingView(onStart: handleStartTapped)
                case .granted:
                    grantedContent
                case .denied:
                    MicDeniedView()
                }
            }
        }
        // When permission becomes granted, (re)start the engine; when it leaves
        // granted, stop it. `.onChange(of:)` fires whenever the value changes.
        .onChange(of: permission.state) { _, newState in
            syncEngine(to: newState)
        }
        // On first appearance, restore the last-used instrument/tuning, apply the
        // user's settings, and (if a returning user) start capturing immediately.
        .task {
            restoreSelection()
            applySettings()
            if !shouldShowPriming {
                syncEngine(to: permission.state)
            }
        }
        // Live-apply settings changes: recalibration (reference pitch), in-tune
        // sensitivity, and the haptics toggle all take effect immediately.
        .onChange(of: settings?.referencePitchHz) { _, _ in applySettings() }
        .onChange(of: settings?.inTuneSensitivity) { _, _ in applySettings() }
        .onChange(of: settings?.hapticsEnabled) { _, _ in applySettings() }
        // Re-check permission when the app becomes active again (e.g. returning
        // from Settings after flipping the mic toggle). `.onChange` of scenePhase
        // is the standard place to react to foreground/background transitions.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                permission.refresh()
            }
        }
    }

    // MARK: Sub-screens

    /// What we show once the mic is granted: the targeted tuning session (which
    /// string, how flat/sharp, latch-on-hold), with the input meter underneath
    /// as a secondary "is sound getting in?" signal. The headstock hero replaces
    /// the session body in slice #06; chromatic mode (#08) brings back the raw
    /// note readout behind a toggle.
    private var grantedContent: some View {
        ZStack {
            backdrop

            VStack(spacing: 20) {
                // Top-left: the instrument/tuning selector pill (opens the picker).
                // Kept left so it never collides with the shell's top-right gear.
                HStack {
                    InstrumentSelectorPill(
                        instrumentName: session.currentInstrument.name,
                        tuningName: session.currentTuning.name,
                        action: { showingPicker = true }
                    )
                    Spacer()
                }

                // The hero: headstock + cents meter (or tone hint) + flourish.
                TunerHeroView(
                    model: session,
                    isToneMode: isToneMode,
                    playingStringIndex: playingStringIndex,
                    onTapPeg: handlePegTap
                )

                // The face controls: capo chip + tone-mode toggle.
                HStack(spacing: 16) {
                    CapoControlView(
                        capo: session.capo,
                        onIncrement: session.incrementCapo,
                        onReset: session.resetCapo
                    )
                    toneModeToggle
                }

                // The level meter, a secondary "is sound getting in?" signal.
                // Hidden in tone-mode (the mic is off then).
                if !isToneMode {
                    InputLevelMeter(level: engine.level)
                        .padding(.horizontal, 40)
                }
            }
            .padding()
        }
        // Drive the session from the detector — but ONLY in tuning mode. In tone-
        // mode the mic is off and we don't want the tuner reacting to its own tone.
        .onChange(of: detector.reading) { _, reading in
            guard !isToneMode else { return }
            session.ingest(reading)
        }
        // Entering/leaving tone-mode flips the audio path (see syncToneMode).
        .onChange(of: isToneMode) { _, on in
            syncToneMode(on)
        }
        // The instrument/tuning picker.
        .sheet(isPresented: $showingPicker) {
            InstrumentPickerView(
                selectedInstrument: session.currentInstrument,
                selectedTuning: session.currentTuning,
                mostUsedInstrumentIDs: selection.mostUsedInstrumentIDs(limit: 3),
                onSelect: { instrument, tuning in
                    session.select(instrument: instrument, tuning: tuning)
                    selection.recordSelection(instrumentID: instrument.id, tuningName: tuning.name)
                },
                onCreateCustom: { /* custom tuning editor — slice #12 */ }
            )
        }
        .ignoresSafeArea()
    }

    /// The tone-mode toggle button (a speaker icon that fills when active).
    private var toneModeToggle: some View {
        Button {
            isToneMode.toggle()
        } label: {
            Image(systemName: isToneMode ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(isToneMode
                        ? GKColor.accent.opacity(0.18)
                        : GKColor.textSecondary.opacity(0.12))
                }
                .foregroundStyle(isToneMode ? GKColor.accent : GKColor.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isToneMode ? "Tone mode on" : "Tone mode off")
        .accessibilityHint("Tap a peg to hear its pitch")
    }

    // MARK: Logic

    /// Show the priming screen only on a genuine first run that hasn't decided
    /// yet. (If a returning user previously granted/denied, skip straight to the
    /// relevant state even if the flag somehow wasn't set.)
    private var shouldShowPriming: Bool {
        !hasCompletedPriming && permission.state == .undetermined
    }

    /// User tapped "Start tuning" on the priming screen. Mark priming done
    /// (so it never shows again) and fire the OS permission prompt.
    private func handleStartTapped() {
        // Persist that we've shown priming, and reflect it in view state so the
        // priming screen won't reappear after the prompt resolves.
        let flag = FirstRunFlag()
        flag.markPrimingComplete()
        hasCompletedPriming = true

        // Request permission. `Task { ... }` launches the async work; when it
        // finishes, `permission.state` updates and `.onChange` starts the engine
        // if we were granted.
        Task {
            await permission.request()
        }
    }

    /// Restore the player's last-used instrument + tuning (persisted on-device),
    /// so the Tuner reopens where they left off instead of cold-starting on guitar.
    private func restoreSelection() {
        let instrument = selection.restoredInstrument()
        session.select(instrument: instrument, tuning: selection.restoredTuning(for: instrument))
    }

    /// Route a peg tap: in tone-mode play that string's target pitch; otherwise
    /// lock onto it for tuning.
    private func handlePegTap(_ index: Int) {
        guard session.targets.indices.contains(index) else { return }
        if isToneMode {
            toneGenerator.play(frequencyHz: session.targets[index].frequencyHz)
        } else {
            session.lock(toStringIndex: index)
        }
    }

    /// Which peg is currently sounding — the target whose frequency matches the
    /// tone generator's. Drives the headstock highlight in tone-mode.
    private var playingStringIndex: Int? {
        guard let hz = toneGenerator.currentFrequencyHz else { return nil }
        return session.targets.firstIndex { abs($0.frequencyHz - hz) < 0.01 }
    }

    /// Flip the audio path when tone-mode toggles. Entering: stop the mic +
    /// detection and switch the session to playback so tones are audible (even on
    /// the silent switch). Leaving: stop the tone and resume detection (the mic
    /// engine re-asserts the record session itself on start).
    private func syncToneMode(_ on: Bool) {
        if on {
            engine.stop()
            detector.reset()
            do {
                try coordinator.configureForPlayback()
            } catch {
                print("AudioSession playback configuration failed: \(error)")
            }
        } else {
            toneGenerator.shutdown()
            syncEngine(to: permission.state)
        }
    }

    /// Push the user's global preferences into the tuning session: A4 reference
    /// pitch, the in-tune sensitivity window, and the haptics toggle. No-op when
    /// no store is injected (e.g. previews) — the session keeps its defaults.
    private func applySettings() {
        guard let settings else { return }
        session.reconfigure(
            referencePitch: ReferencePitch(hertz: settings.referencePitchHz),
            tolerance: TuningTolerance(
                inTuneCents: settings.inTuneSensitivity.centsTolerance,
                perfectCents: 1,
                holdDuration: 0.7
            )
        )
        session.hapticsEnabled = settings.hapticsEnabled
    }

    /// Start or stop the audio engine to match the permission state.
    private func syncEngine(to state: MicPermissionState) {
        switch state {
        case .granted:
            // Subscribe the detector to the engine's buffers BEFORE starting, so
            // it's wired up the moment audio begins flowing. Re-attaching is
            // harmless (it just re-sets the single buffer handler).
            detector.attach(to: engine)
            do {
                try engine.start()
            } catch {
                // Starting can fail if another app holds the mic. We don't crash;
                // the readout simply stays idle. A future slice can surface a
                // gentle error; for this slice silence is acceptable.
                print("AudioInputEngine failed to start: \(error)")
            }
        case .denied, .undetermined:
            engine.stop()
            // Clear any lingering reading + session state so nothing stale hangs
            // on screen and a fresh session starts clean next time. Also tear down
            // the tone generator + release the audio session.
            detector.reset()
            session.reset()
            toneGenerator.shutdown()
            coordinator.deactivate()
        }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [GKColor.accent.opacity(0.18), GKColor.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    TunerView()
}
