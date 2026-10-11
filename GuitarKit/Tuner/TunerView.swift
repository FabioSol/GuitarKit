//
//  TunerView.swift
//  GuitarKit
//
//  The Tuner tab's top-level screen. It decides, based on first-run state + mic
//  permission, WHICH sub-screen to show:
//
//      first launch & undetermined  → MicPrimingView   (value screen → prompt)
//      granted                      → the tuner face    (audio flows!)
//      denied                       → MicDeniedView     (recoverable, → Settings)
//
//  THE AUDIO BRAIN LIVES ELSEWHERE: the engine/detector/tone/session and the
//  tricky mode transitions (targeted ⇄ tone ⇄ chromatic) all live in
//  `TunerCoordinator`, which is unit-tested in isolation. This view keeps only
//  what's genuinely view-layer — permission (it picks the sub-screen), the shared
//  instrument/tuning stores, the settings, and the sheets — and forwards events to
//  the coordinator.
//

import SwiftUI

struct TunerView: View {

    // MARK: Owned state

    /// The audio brain: owns the engine, detector, tone generator, session, and
    /// the targeted/tone/chromatic mode transitions. OWNED BY THE APP SHELL
    /// (`RootView`), not this view: the shell rebuilds tool screens on every
    /// switch, and the coordinator — with the player's tuning progress — must
    /// outlive that. This view starts/stops listening as it appears/leaves.
    let coordinator: TunerCoordinator

    /// The microphone-permission model. Drives which sub-screen we show, so it
    /// stays here in the view rather than in the coordinator.
    @State private var permission = MicrophonePermission()

    /// The shared instrument/tuning selection and custom tunings — read
    /// through the coordinator, which is also their only writer.
    private var selection: InstrumentSelectionStore { coordinator.selection }
    private var customTunings: CustomTuningStore { coordinator.customTunings }

    #if DEBUG
    @State private var devConfig = TunerDevConfig()
    @State private var showingDevPanel = false
    #endif

    /// Which sheet (if any) is up.
    @State private var activeSheet: TunerSheet?

    private enum TunerSheet: Identifiable {
        case picker
        case customEditor(strings: [Note])
        var id: String {
            switch self {
            case .picker:       return "picker"
            case .customEditor: return "editor"
            }
        }
    }

    @State private var hasCompletedPriming = FirstRunFlag().hasCompletedPriming

    @Environment(\.scenePhase) private var scenePhase

    @Environment(SettingsStore.self) private var settings: SettingsStore?

    // MARK: Body

    var body: some View {
        Group {
            if shouldShowPriming {
                MicPrimingView(onStart: handleStartTapped)
            } else {
                switch permission.state {
                case .undetermined:
                    MicPrimingView(onStart: handleStartTapped)
                case .granted:
                    grantedContent
                case .denied:
                    MicDeniedView()
                }
            }
        }
        // Bubble the priming state up so RootView can hide the nav bar while
        // the priming screen is showing (nav there is confusing and overlaps).
        .preference(key: TunerPrimingKey.self, value: shouldShowPriming)
        .onChange(of: permission.state) { _, newState in
            coordinator.syncEngine(to: newState)
        }
        .task {
            applySettings()
            #if DEBUG
            // Start the Lab's in-tune slider FROM the user's Settings, so the
            // Lab only overrides Settings once its slider is actually moved.
            if let settings { devConfig.inTuneThresholdCents = settings.inTuneSensitivity.centsTolerance }
            applyDevOverrides()
            #endif
            // Restore the saved instrument/tuning LAST: selecting it rebuilds
            // the targets, which re-derives the detector's tuning band — so the
            // band reflects the restored tuning and (in DEBUG) isn't clobbered
            // by the dev-override pass above.
            restoreSelection()
            coordinator.onAppear(permission: permission.state, isPriming: shouldShowPriming)
        }
        .onDisappear { coordinator.onLeave() }
        .onChange(of: settings?.referencePitchHz) { _, _ in applySettings() }
        .onChange(of: settings?.inTuneSensitivity) { _, _ in applySettings() }
        .onChange(of: settings?.hapticsEnabled) { _, _ in applySettings() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                permission.refresh()
                coordinator.onBecameActive(permission: permission.state, isPriming: shouldShowPriming)
            }
        }
    }

    // MARK: Sub-screens

    private var grantedContent: some View {
        ZStack {
            backdrop

            VStack(spacing: 20) {
                if !coordinator.isChromaticMode {
                    InstrumentSelectorPill(
                        instrumentName: coordinator.session.currentInstrument.name,
                        tuningName: coordinator.session.currentTuning.name,
                        action: { activeSheet = .picker }
                    )
                }

                HeroFlip(isFlipped: coordinator.isChromaticMode) {
                    TunerHeroView(
                        model: coordinator.session,
                        isToneMode: coordinator.isToneMode,
                        playingStringIndex: coordinator.playingStringIndex,
                        onTapPeg: coordinator.handlePegTap
                    )
                } back: {
                    LiveChromaticReadout(detector: coordinator.detector)
                }

                HStack(spacing: 16) {
                    if !coordinator.isChromaticMode {
                        CapoControlView(
                            capo: coordinator.session.capo,
                            onIncrement: coordinator.session.incrementCapo,
                            onDecrement: coordinator.session.decrementCapo,
                            onReset: coordinator.session.resetCapo
                        )
                        toneModeToggle
                    }
                    chromaticModeToggle
                    #if DEBUG
                    devPanelButton
                    #endif
                }

                if !coordinator.isToneMode {
                    LiveLevelMeter(engine: coordinator.engine)
                        .padding(.horizontal, 40)
                }
            }
            .padding()
            .padding(.bottom, 90)
        }
        .sheet(item: $activeSheet, onDismiss: { coordinator.onSheetDismiss(permission: permission.state) }) { sheet in
            switch sheet {
            case .picker:
                InstrumentPickerView(
                    selectedInstrument: coordinator.session.currentInstrument,
                    selectedTuning: coordinator.session.currentTuning,
                    mostUsedInstrumentIDs: selection.mostUsedInstrumentIDs(limit: 3),
                    onSelect: coordinator.select,
                    onCreateCustom: {
                        // Lift the detection band while the editor is up so its
                        // capture-by-playing can hear notes outside the current
                        // tuning; the sheet's onDismiss restores it.
                        coordinator.onEditorOpened()
                        activeSheet = .customEditor(strings: coordinator.session.currentTuning.strings)
                    },
                    customTunings: { customTunings.tunings(forInstrumentID: $0.id) },
                    onDeleteCustom: { instrument, tuning in
                        coordinator.deleteCustomTuning(named: tuning.name, for: instrument)
                    }
                )
            case .customEditor(let strings):
                CustomTuningEditorView(
                    initialStrings: strings,
                    instrument: coordinator.session.currentInstrument,
                    onHear: handleHearNote,
                    detectedNote: { coordinator.detector.reading?.note },
                    onSave: coordinator.saveCustomTuning
                )
            }
        }
        .ignoresSafeArea()
        #if DEBUG
        .sheet(isPresented: $showingDevPanel) {
            TunerDevPanelView(
                config: devConfig,
                recorder: coordinator.clipRecorder,
                targets: coordinator.session.targets,
                makeClipMetadata: clipMetadata
            ) { showingDevPanel = false }
        }
        .onChange(of: devConfig.inTuneThresholdCents) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.smoothing) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.clarityThreshold) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.levelGateDB) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.algorithm) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.preprocessEnabled) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.harmonicGate) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.engine) { _, _ in applyDevOverrides() }
        #endif
    }

    private var toneModeToggle: some View {
        Button {
            coordinator.setToneMode(!coordinator.isToneMode, permission: permission.state)
        } label: {
            Image(systemName: coordinator.isToneMode ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(coordinator.isToneMode
                        ? GKColor.accent.opacity(0.18)
                        : GKColor.textSecondary.opacity(0.12))
                }
                .foregroundStyle(coordinator.isToneMode ? GKColor.accent : GKColor.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(coordinator.isToneMode ? "Tone mode on" : "Tone mode off")
        .accessibilityHint("Tap a peg to hear its pitch")
    }

    private var chromaticModeToggle: some View {
        Button {
            coordinator.setChromatic(!coordinator.isChromaticMode, permission: permission.state)
        } label: {
            Image(systemName: "tuningfork")
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(coordinator.isChromaticMode
                        ? GKColor.accent.opacity(0.18)
                        : GKColor.textSecondary.opacity(0.12))
                }
                .foregroundStyle(coordinator.isChromaticMode ? GKColor.accent : GKColor.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(coordinator.isChromaticMode ? "Chromatic mode on" : "Chromatic mode off")
        .accessibilityHint("Names the nearest note for any pitch")
    }

    // MARK: Logic

    private var shouldShowPriming: Bool {
        !hasCompletedPriming && permission.state == .undetermined
    }

    private func handleStartTapped() {
        let flag = FirstRunFlag()
        flag.markPrimingComplete()
        hasCompletedPriming = true
        Task {
            await permission.request()
        }
    }

    private func restoreSelection() {
        coordinator.restoreSelectionOnce()
    }

    private func handleHearNote(_ note: Note) {
        let hz = settings?.referencePitchHz ?? ReferencePitch.standard.hertz
        let calculator = PitchCalculator(referenceA: ReferencePitch(hertz: hz))
        coordinator.playHearNote(frequencyHz: calculator.frequency(of: note))
    }

    private func applySettings() {
        guard let settings else { return }
        coordinator.session.reconfigure(
            referencePitch: ReferencePitch(hertz: settings.referencePitchHz),
            tolerance: TuningTolerance(
                inTuneCents: settings.inTuneSensitivity.centsTolerance,
                perfectCents: 1,
                holdDuration: 0.7
            )
        )
        coordinator.session.hapticsEnabled = settings.hapticsEnabled
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [GKColor.accent.opacity(0.18), GKColor.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    #if DEBUG
    private var devPanelButton: some View {
        Button {
            showingDevPanel = true
        } label: {
            Image(systemName: "flask")
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background { Capsule().fill(GKColor.textSecondary.opacity(0.12)) }
                .foregroundStyle(GKColor.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tuner Lab (developer)")
    }

    private func applyDevOverrides() {
        let hz = settings?.referencePitchHz ?? ReferencePitch.standard.hertz
        coordinator.session.reconfigure(
            referencePitch: ReferencePitch(hertz: hz),
            tolerance: TuningTolerance(
                inTuneCents: devConfig.inTuneThresholdCents,
                perfectCents: 1,
                holdDuration: 0.7
            )
        )
        coordinator.detector.config.smoothing = Float(devConfig.smoothing)
        coordinator.detector.config.clarityThreshold = Float(devConfig.clarityThreshold)
        coordinator.detector.config.levelGateDB = Float(devConfig.levelGateDB)
        coordinator.detector.config.algorithm = devConfig.algorithm
        coordinator.detector.config.preprocessingEnabled = devConfig.preprocessEnabled
        coordinator.targetedHarmonicGate = Float(devConfig.harmonicGate)
        coordinator.detector.config.engine = devConfig.engine
    }

    /// The label + replay context for a new Lab clip: which string (or `nil`
    /// for noise only), plus the band/calibration/tuning in force right now.
    private func clipMetadata(target: PitchTarget?,
                              pluck: PitchClipRecorder.Pluck?,
                              background: PitchClipRecorder.Background) -> PitchClipRecorder.Metadata {
        let config = coordinator.detector.config
        return PitchClipRecorder.Metadata(
            note: target?.note.name,
            expectedHz: target?.frequencyHz,
            pluck: target == nil ? nil : pluck,
            background: background,
            instrument: coordinator.session.currentInstrument.name,
            tuning: coordinator.session.currentTuning.name,
            referenceA: config.referencePitch.hertz,
            bandMinHz: config.band.minFrequencyHz,
            bandMaxHz: config.band.maxFrequencyHz,
            highPassHz: config.band.highPassHz,
            lowPassHz: config.band.lowPassHz,
            targetsHz: config.targetsHz
        )
    }
    #endif
}

// MARK: - Live sub-views
//
// The mic level and the detector reading change ~10 times a second. If
// `TunerView`'s own body read them, SwiftUI would re-evaluate the WHOLE tuner
// screen (headstock, pill, buttons…) on every audio buffer. These two tiny
// views read the fast-changing value themselves, so only they redraw.

/// The input level meter, observing the engine's `level` directly.
private struct LiveLevelMeter: View {
    let engine: AudioInputProviding
    var body: some View { InputLevelMeter(level: engine.level) }
}

/// The chromatic readout, observing the detector's `reading` directly.
private struct LiveChromaticReadout: View {
    let detector: PitchDetecting
    var body: some View { ChromaticReadoutView(reading: detector.reading) }
}

/// Preference key that bubbles the priming state up to `RootView` so it can
/// hide the nav bar and settings button while the first-run screen is showing.
struct TunerPrimingKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

#Preview {
    TunerView(coordinator: TunerCoordinator())
}
