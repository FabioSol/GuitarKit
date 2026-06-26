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
    /// the targeted/tone/chromatic mode transitions.
    @State private var coordinator = TunerCoordinator()

    /// The microphone-permission model. Drives which sub-screen we show, so it
    /// stays here in the view rather than in the coordinator.
    @State private var permission = MicrophonePermission()

    /// The picker's persistent memory (last-used instrument/tuning + usage counts)
    /// and the player's saved custom tunings. Both are SHARED stores the app shell
    /// owns and injects, so the tuning the player picks/saves here also drives the
    /// tuning-aware Chords/Scales tools. We fall back to owned instances only when
    /// nothing was injected (e.g. SwiftUI previews), via the accessors below.
    @Environment(InstrumentSelectionStore.self) private var injectedSelection: InstrumentSelectionStore?
    @Environment(CustomTuningStore.self) private var injectedCustomTunings: CustomTuningStore?
    @State private var ownedSelection = InstrumentSelectionStore()
    @State private var ownedCustomTunings = CustomTuningStore()

    private var selection: InstrumentSelectionStore { injectedSelection ?? ownedSelection }
    private var customTunings: CustomTuningStore { injectedCustomTunings ?? ownedCustomTunings }

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
        .onChange(of: permission.state) { _, newState in
            coordinator.syncEngine(to: newState)
        }
        .task {
            restoreSelection()
            applySettings()
            #if DEBUG
            applyDevOverrides()
            #endif
            coordinator.onAppear(permission: permission.state, isPriming: shouldShowPriming)
        }
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
                    ChromaticReadoutView(reading: coordinator.detector.reading)
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
                    InputLevelMeter(level: coordinator.engine.level)
                        .padding(.horizontal, 40)
                }
            }
            .padding()
            .padding(.bottom, 90)
        }
        .onChange(of: coordinator.detector.reading) { _, reading in
            coordinator.handleDetectorReading(reading)
        }
        .sheet(item: $activeSheet, onDismiss: { coordinator.onSheetDismiss(permission: permission.state) }) { sheet in
            switch sheet {
            case .picker:
                InstrumentPickerView(
                    selectedInstrument: coordinator.session.currentInstrument,
                    selectedTuning: coordinator.session.currentTuning,
                    mostUsedInstrumentIDs: selection.mostUsedInstrumentIDs(limit: 3),
                    onSelect: { instrument, tuning in
                        coordinator.session.select(instrument: instrument, tuning: tuning)
                        selection.recordSelection(instrumentID: instrument.id, tuningName: tuning.name)
                    },
                    onCreateCustom: {
                        activeSheet = .customEditor(strings: coordinator.session.currentTuning.strings)
                    },
                    customTunings: { customTunings.tunings(forInstrumentID: $0.id) },
                    onDeleteCustom: { instrument, tuning in
                        customTunings.delete(named: tuning.name, forInstrumentID: instrument.id)
                    }
                )
            case .customEditor(let strings):
                CustomTuningEditorView(
                    initialStrings: strings,
                    instrument: coordinator.session.currentInstrument,
                    onHear: handleHearNote,
                    detectedNote: { coordinator.detector.reading?.note },
                    onSave: handleSaveCustomTuning
                )
            }
        }
        .ignoresSafeArea()
        #if DEBUG
        .sheet(isPresented: $showingDevPanel) {
            TunerDevPanelView(config: devConfig) { showingDevPanel = false }
        }
        .onChange(of: devConfig.inTuneThresholdCents) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.smoothing) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.clarityThreshold) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.levelGateDB) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.algorithm) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.preprocessEnabled) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.preprocessLowPassHz) { _, _ in applyDevOverrides() }
        .onChange(of: devConfig.preprocessHighPassHz) { _, _ in applyDevOverrides() }
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
        let instrument = selection.restoredInstrument()
        let customs = customTunings.tunings(forInstrumentID: instrument.id)
        coordinator.session.select(
            instrument: instrument,
            tuning: selection.restoredTuning(for: instrument, customTunings: customs)
        )
    }

    private func handleHearNote(_ note: Note) {
        let hz = settings?.referencePitchHz ?? ReferencePitch.standard.hertz
        let calculator = PitchCalculator(referenceA: ReferencePitch(hertz: hz))
        coordinator.playHearNote(frequencyHz: calculator.frequency(of: note))
    }

    private func handleSaveCustomTuning(_ tuning: Tuning) {
        let instrument = coordinator.session.currentInstrument
        customTunings.save(tuning, forInstrumentID: instrument.id)
        coordinator.session.select(instrument: instrument, tuning: tuning)
        selection.recordSelection(instrumentID: instrument.id, tuningName: tuning.name)
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
        guard let mpm = coordinator.detector as? MPMPitchDetector else { return }
        mpm.setSmoothing(emaFactor: Float(devConfig.smoothing))
        mpm.setClarityThreshold(Float(devConfig.clarityThreshold))
        mpm.setLevelGate(dB: Float(devConfig.levelGateDB))
        mpm.setAlgorithm(devConfig.algorithm)
        mpm.setPreprocessing(enabled: devConfig.preprocessEnabled)
        mpm.setPreprocessorCutoffs(highPassHz: devConfig.preprocessHighPassHz,
                                   lowPassHz: devConfig.preprocessLowPassHz)
    }
    #endif
}

#Preview {
    TunerView()
}
