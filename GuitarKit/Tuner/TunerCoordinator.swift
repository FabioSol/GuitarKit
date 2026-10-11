//
//  TunerCoordinator.swift
//  GuitarKit
//
//  The Tuner's AUDIO BRAIN: it owns the mic engine, the pitch detector, the
//  tone generator and the tuning session, and decides every transition
//  between the Tuner's modes (targeted / tone / chromatic), sheets, and app
//  lifecycle.
//
//  WHY A SEPARATE OBJECT (not `@State` in `TunerView`)?
//  Those transitions are where the subtle bugs live — e.g. a sheet dismiss
//  must restart the mic only if the sheet actually switched to playback;
//  leaving chromatic mode must clear the targeted session's stale progress;
//  returning to the foreground must revive a mic that stopped while the
//  permission stayed the same. Here each one is a plain method over
//  collaborators behind small protocols, so tests drive them with silent
//  fakes — no SwiftUI, no hardware.
//
//  The app shell (`RootView`) owns it, so the player's tuning progress
//  survives switching tools; `TunerView` is a thin shell that binds to its
//  state and forwards events. `MicrophonePermission` stays in the view (it
//  decides WHICH sub-screen shows); the coordinator takes the resolved
//  `MicPermissionState` as a parameter, which keeps its logic hardware-free.
//

import Foundation
import Observation

@MainActor
@Observable
final class TunerCoordinator {

    // MARK: - What the audio session is currently configured for
    //
    // We track this so we only RESTORE recording when we actually left it: a
    // sheet dismiss restarts the mic only if the sheet (the custom-tuning
    // editor's tap-to-hear) had switched us to playback — not after the player
    // merely browsed the picker.

    enum AudioRoute: Equatable {
        case idle        // nothing configured / released
        case recording   // mic capturing for detection
        case playback    // speaker out for tones (mic off)
    }

    /// The current audio route. Observed so future UI could reflect it; primarily
    /// it gates the restore-on-dismiss decision.
    private(set) var audioRoute: AudioRoute = .idle

    // MARK: - Mode state (observed → drives the view)

    /// Tone-mode: detection paused (mic off, session → playback), tapping a peg
    /// plays its pitch instead of locking onto it.
    private(set) var isToneMode = false

    /// Chromatic mode: the hero flips to name the nearest note for ANY pitch. The
    /// mic stays on; the targeted-tuning session is bypassed while it's on.
    private(set) var isChromaticMode = false

    /// The peg index we last asked the tone generator to play, so the headstock can
    /// highlight EXACTLY that peg even when two strings share a target frequency.
    private(set) var tonePegIndex: Int?

    /// Whether the custom-tuning editor is up. Its capture-by-playing flow must
    /// hear notes OUTSIDE the current tuning (that's the point of editing), so
    /// while it's open the detector runs the full band instead of the
    /// tuning-derived one.
    private var isEditorCapture = false

    // MARK: - Owned collaborators (behind seams for testability)

    /// THE instrument/tuning selection (persisted, shared with Chords/Scales,
    /// and the owner of the custom tunings). The coordinator is its only
    /// writer — `select` records the choice AND retunes the session in one
    /// step, so the two can never disagree.
    @ObservationIgnored let selection: InstrumentSelectionStore

    /// The player's saved custom tunings (owned by `selection`).
    var customTunings: CustomTuningStore { selection.customTunings ?? Self.fallbackCustoms }

    /// The targeted-tuning state machine bridge. Pure-ish logic; safe to use real
    /// in tests.
    let session: TuningSessionModel

    /// The mic capture engine — its `level` feeds the meter, its buffers feed the
    /// detector. `AudioInputProviding` so tests pass a fake.
    @ObservationIgnored let engine: AudioInputProviding

    /// The pitch detector. `PitchDetecting` so tests pass a fake; the view reads
    /// `detector.reading` for the chromatic readout.
    @ObservationIgnored let detector: PitchDetecting

    /// The tone generator (tap-to-hear). `TonePlaying` so tests pass a silent fake.
    @ObservationIgnored let tone: TonePlaying

    /// Switches the shared audio session between record/playback. Behind
    /// `AudioSessionConfiguring` so tests can record the requests.
    @ObservationIgnored let audioSession: AudioSessionConfiguring

    /// The harmonic check's gate in TARGETED mode (see `PitchTrackerConfig`).
    /// Chromatic mode and editor capture always run with it off. A property
    /// (not a constant) so the Tuner Lab can A/B it live; the coordinator
    /// re-applies it on every mode change, so the two never fight.
    @ObservationIgnored var targetedHarmonicGate = PitchTrackerConfig.targetedModeHarmonicGate {
        didSet { applySessionContext() }
    }

    #if DEBUG
    /// The Tuner Lab's clip recorder (debug builds only; `nil` when tests
    /// inject a fake detector).
    @ObservationIgnored private(set) var clipRecorder: PitchClipRecorder?
    #endif

    // MARK: - Init

    /// Production init: builds the real, hardware-backed collaborators. We
    /// construct them in the body (not as default arguments) because they're
    /// `@MainActor` initializers, which can't be called from a default-argument
    /// context under this project's main-actor-by-default isolation.
    /// - Parameter selection: the app's shared instrument/tuning selection (it
    ///   also knows the custom tunings). `nil` → a private, in-memory one
    ///   (previews).
    convenience init(selection: InstrumentSelectionStore? = nil) {
        let detector = PitchDetector()
        #if DEBUG
        // The Tuner Lab's clip recorder taps the detector's input, so a clip
        // holds exactly the samples the live tracker processed.
        let recorder = PitchClipRecorder()
        detector.clipRecorder = recorder
        #endif
        self.init(
            session: TuningSessionModel(),
            engine: AudioInputEngine(),
            detector: detector,
            tone: ToneGenerator(),
            audioSession: AudioSessionCoordinator.shared.client(),
            selection: selection
        )
        #if DEBUG
        clipRecorder = recorder
        #endif
    }

    /// Designated init: inject collaborators (tests pass fakes).
    init(
        session: TuningSessionModel,
        engine: AudioInputProviding,
        detector: PitchDetecting,
        tone: TonePlaying,
        audioSession: AudioSessionConfiguring,
        selection: InstrumentSelectionStore? = nil
    ) {
        self.selection = selection ?? Self.privateSelection()
        self.session = session
        self.engine = engine
        self.detector = detector
        self.tone = tone
        self.audioSession = audioSession

        // Keep the detector glued to the session: every tuning/capo/calibration
        // change rebuilds the targets, which fires this hook. Applied once now
        // so the cold-start tuning gets its band before the first rebuild.
        session.onTargetsRebuilt = { [weak self] in self?.applySessionContext() }
        applySessionContext()

        // Every detector reading (on the main actor, once per ~0.1 s window)
        // goes straight to the session — no view in between.
        detector.onReading = { [weak self] reading in self?.handleDetectorReading(reading) }
    }

    // MARK: - Session → detector (band + calibration)

    /// Point the detector at the current state:
    ///   • the BAND — tuning-derived in targeted mode, full when a mode needs
    ///     to hear arbitrary pitches (chromatic naming, editor capture);
    ///   • the HARMONIC CHECK and the STRING TARGETS (which the probabilistic
    ///     engine tracks) — on in targeted mode, off when any sound must be
    ///     heard;
    ///   • the REFERENCE PITCH — so chromatic note names use the same A4 as
    ///     the targeted tuner.
    /// Cheap to call redundantly — the tracker no-ops on unchanged values.
    private func applySessionContext() {
        if isChromaticMode || isEditorCapture {
            detector.config.band = .full
            detector.config.harmonicGate = 0
            detector.config.targetsHz = []        // the probabilistic engine needs strings
        } else {
            // An empty tuning (the never-expected placeholder) yields no band;
            // fall back to full rather than detecting nothing.
            detector.config.band = DetectionBand.around(targets: session.targets) ?? .full
            detector.config.harmonicGate = targetedHarmonicGate
            detector.config.targetsHz = session.targets.map(\.frequencyHz)
        }
        detector.config.referencePitch = session.referencePitch
    }

    /// The custom-tuning editor opened: lift the band so capture-by-playing
    /// hears any note. `onSheetDismiss` restores it.
    func onEditorOpened() {
        isEditorCapture = true
        applySessionContext()
    }

    // MARK: - Engine lifecycle

    /// Start or stop capture to match the permission state. Granted → wire the
    /// detector to the engine and start; otherwise stop everything and release the
    /// session.
    func syncEngine(to state: MicPermissionState) {
        switch state {
        case .granted:
            // Re-attaching is harmless (it just re-sets the single buffer handler);
            // doing it before start guarantees the detector is wired the moment
            // audio flows. `start()` is idempotent, so a redundant call is a no-op.
            detector.attach(to: engine)
            do {
                // State our need first: the shared session owner switches to
                // recording (or keeps it, if it already is) before the mic starts.
                try audioSession.configureForRecording()
                try engine.start()
                audioRoute = .recording
            } catch {
                print("AudioInputEngine failed to start: \(error)")
            }
        case .denied, .undetermined:
            engine.stop()
            detector.reset()
            session.reset()
            tone.shutdown()
            audioSession.deactivate()
            audioRoute = .idle
        }
    }

    /// Initial setup when the Tuner appears: if we're not still on the priming
    /// screen, start capture for the current permission.
    func onAppear(permission: MicPermissionState, isPriming: Bool) {
        guard !isPriming else { return }
        syncEngine(to: permission)
    }

    /// Whether the saved instrument/tuning has been restored into the session.
    /// The coordinator outlives the Tuner screen (the app shell owns it), so
    /// the restore must happen once — not on every return to the Tuner, which
    /// would rebuild the session and wipe the strings already tuned.
    @ObservationIgnored private(set) var hasRestoredSelection = false

    /// Restore the player's saved instrument + tuning into the session, once.
    func restoreSelectionOnce() {
        guard !hasRestoredSelection else { return }
        hasRestoredSelection = true
        session.select(instrument: selection.currentInstrument, tuning: selection.currentTuning)
    }

    // MARK: - Choosing instruments and tunings (the single write path)

    /// The player picked an instrument + tuning: remember it (for relaunch and
    /// for Chords/Scales) and retune the session.
    func select(instrument: Instrument, tuning: Tuning) {
        selection.recordSelection(instrumentID: instrument.id, tuningName: tuning.name)
        session.select(instrument: instrument, tuning: tuning)
    }

    /// Save a custom tuning for the current instrument and switch to it.
    func saveCustomTuning(_ tuning: Tuning) {
        let instrument = session.currentInstrument
        customTunings.save(tuning, forInstrumentID: instrument.id)
        select(instrument: instrument, tuning: tuning)
    }

    /// Delete one of an instrument's saved custom tunings.
    func deleteCustomTuning(named name: String, for instrument: Instrument) {
        customTunings.delete(named: name, forInstrumentID: instrument.id)
    }

    /// Previews/tests without the app's shared selection get a private one on
    /// a throwaway UserDefaults suite — never the player's real preferences.
    private static func privateSelection() -> InstrumentSelectionStore {
        let suite = "guitarkit.private.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return InstrumentSelectionStore(defaults: defaults,
                                        customTunings: CustomTuningStore(defaults: defaults))
    }
    private static let fallbackCustoms: CustomTuningStore = {
        let suite = "guitarkit.private.customs"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return CustomTuningStore(defaults: defaults)
    }()

    /// The player left the Tuner for another tool: stop listening (mic off —
    /// battery, privacy, and the orange mic indicator) and silence any
    /// reference tone. The tuning session — instrument, capo, strings already
    /// latched — is kept for when they come back. Releasing the Tuner's audio
    /// need is safe: the shared session owner only deactivates once no other
    /// tool (e.g. a playing metronome) needs audio either.
    func onLeave() {
        engine.stop()
        detector.reset()
        tone.shutdown()
        audioSession.deactivate()
        if isToneMode {
            isToneMode = false
            tonePegIndex = nil
        }
        audioRoute = .idle
    }

    /// The app returned to the foreground. The view has just refreshed permission;
    /// we re-assert the engine so a mic that stopped in the background comes back.
    /// Nothing else would: `.onChange(of: permission)` can't see an *unchanged*
    /// grant.
    ///
    /// CRUCIAL GUARD: we only act when the engine is ACTUALLY dead. Scene phase can
    /// flip to `.active` repeatedly (notifications, Control Center, audio-route
    /// changes), and re-running `syncEngine` on a HEALTHY engine re-attaches the tap
    /// + re-touches the audio session every time — enough to thrash the session on a
    /// real device ("reconfig pending" churn) and stutter the UI. When the engine is
    /// already running there's nothing to revive, so we do nothing. Also skipped
    /// while priming (no audio yet) or in tone-mode (mic intentionally off).
    func onBecameActive(permission: MicPermissionState, isPriming: Bool) {
        guard !isPriming, !isToneMode, !engine.isRunning else { return }
        syncEngine(to: permission)
    }

    // MARK: - Detector → session

    /// Feed a detector reading into the targeted session — but ONLY in targeted
    /// mode. Tone-mode has no mic; chromatic mode reads the detector directly and
    /// bypasses the session's targets/haptics.
    func handleDetectorReading(_ reading: PitchReading?) {
        guard !isToneMode, !isChromaticMode else { return }
        session.ingest(reading)
    }

    // MARK: - Tone mode

    /// Toggle tone-mode. Entering: stop the mic + detection and switch to playback
    /// so tones are audible (even on the silent switch). Leaving: stop the tone and
    /// resume capture for the current permission.
    func setToneMode(_ on: Bool, permission: MicPermissionState) {
        isToneMode = on
        if on {
            engine.stop()
            detector.reset()
            do {
                try audioSession.configureForPlayback()
                audioRoute = .playback
            } catch {
                print("AudioSession playback configuration failed: \(error)")
            }
        } else {
            tone.shutdown()
            tonePegIndex = nil
            syncEngine(to: permission)
        }
    }

    // MARK: - Chromatic mode

    /// Toggle chromatic mode. Turning ON forces tone-mode off (chromatic needs the
    /// mic). Turning OFF resets the targeted session: it was bypassed while
    /// chromatic was on, so it would otherwise return holding stale
    /// latches/zone. `session.reset()` keeps the chosen
    /// instrument/tuning/capo and only clears the live progress.
    func setChromatic(_ on: Bool, permission: MicPermissionState) {
        isChromaticMode = on
        if on {
            if isToneMode { setToneMode(false, permission: permission) }
            // Chromatic names ANY pitch, so the tuning-derived band must not
            // clip it — widen to the full range.
            applySessionContext()
        } else {
            // `session.reset()` rebuilds the targets, which re-fires the
            // `onTargetsRebuilt` hook — restoring the tuning band as a side
            // effect, now that `isChromaticMode` is already false.
            session.reset()
        }
    }

    // MARK: - Peg taps

    /// Route a peg tap: in tone-mode play that string's target pitch (remembering
    /// the index for the highlight); otherwise lock/unlock the string for tuning.
    /// A second tap on the already-locked string clears the lock, returning to
    /// auto-detect — so the user can escape a manual lock without any extra button.
    func handlePegTap(_ index: Int) {
        guard session.targets.indices.contains(index) else { return }
        if isToneMode {
            tonePegIndex = index
            tone.play(frequencyHz: session.targets[index].frequencyHz)
        } else if session.isManuallyLocked && session.activeStringIndex == index {
            session.clearLock()
        } else {
            session.lock(toStringIndex: index)
        }
    }

    /// Which peg is currently sounding, for the tone-mode headstock highlight. We
    /// use the remembered index (not a frequency reverse-match, which picks the
    /// wrong peg when two strings share a pitch) and gate on the tone still playing.
    var playingStringIndex: Int? {
        guard tone.currentFrequencyHz != nil else { return nil }
        guard let index = tonePegIndex, session.targets.indices.contains(index) else { return nil }
        return index
    }

    // MARK: - Custom-tuning editor tap-to-hear

    /// Play a one-off note for the editor's "hear" button: switch to playback and
    /// sound it. The route flips to `.playback`, so `onSheetDismiss` knows to
    /// restore recording afterward.
    func playHearNote(frequencyHz: Double) {
        do {
            try audioSession.configureForPlayback()
            audioRoute = .playback
        } catch {
            print("AudioSession playback configuration failed: \(error)")
        }
        tone.play(frequencyHz: frequencyHz)
    }

    // MARK: - Sheet dismiss

    /// A picker/editor sheet closed. Restore the recording session ONLY if a sheet
    /// actually switched us to playback (the editor's tap-to-hear) — just browsing
    /// the picker leaves the mic alone. Tone-mode is left untouched too: its
    /// playback route is deliberate.
    func onSheetDismiss(permission: MicPermissionState) {
        // If the editor had lifted the detection band for capture-by-playing,
        // restore the tuning band. Independent of the audio-route restore
        // below — the band is detector state, not session/route state.
        if isEditorCapture {
            isEditorCapture = false
            applySessionContext()
        }
        guard audioRoute == .playback, !isToneMode else { return }
        tone.shutdown()
        syncEngine(to: permission)
    }
}
