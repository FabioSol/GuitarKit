//
//  TunerCoordinator.swift
//  GuitarKit
//
//  The Tuner's AUDIO BRAIN, lifted out of `TunerView`.
//
//  WHY THIS EXISTS:
//  `TunerView` had grown into an 11-`@State` "god object" that owned the audio
//  engine, detector, tone generator, session, and three interacting MODE flags
//  (targeted / tone / chromatic) — and hand-wove the tricky transitions between
//  them inline. That made the transitions impossible to unit-test (they were
//  tangled with SwiftUI) and let three real lifecycle bugs hide:
//
//    (a) EVERY sheet dismiss restarted the mic, even when the user just opened and
//        closed the picker without playing anything.
//    (b) Leaving CHROMATIC mode never cleared the targeted-tuning session, so it
//        came back showing stale latches/zone from before.
//    (c) Returning to the foreground refreshed permission but never re-asserted the
//        engine — so if the mic had stopped in the background while permission was
//        unchanged, it stayed dead.
//
//  This coordinator owns the audio collaborators (behind small protocols, so tests
//  can swap in silent fakes) and exposes intent methods — `setToneMode`,
//  `setChromatic`, `onSheetDismiss`, `onBecameActive`, … — each of which is a pure
//  decision over those collaborators. The view shrinks to a thin shell that binds
//  to the coordinator's state and forwards events. `MicrophonePermission` and the
//  user-facing stores stay in the view (they decide WHICH sub-screen shows); the
//  coordinator takes the resolved `MicPermissionState` as a parameter, which keeps
//  its logic free of hardware and therefore testable.
//

import Foundation
import Observation

@MainActor
@Observable
final class TunerCoordinator {

    // MARK: - What the audio session is currently configured for
    //
    // We track this so we only RESTORE recording when we actually left it. That's
    // the fix for bug (a): the old code blindly restarted the mic on every sheet
    // dismiss; now we restart only if a sheet (the custom-tuning editor's
    // tap-to-hear) had switched us to playback.

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

    // MARK: - Owned collaborators (behind seams for testability)

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

    // MARK: - Init

    /// Production init: builds the real, hardware-backed collaborators. We
    /// construct them in the body (not as default arguments) because they're
    /// `@MainActor` initializers, which can't be called from a default-argument
    /// context under this project's main-actor-by-default isolation.
    convenience init() {
        self.init(
            session: TuningSessionModel(),
            engine: AudioInputEngine(),
            detector: MPMPitchDetector(),
            tone: ToneGenerator(),
            audioSession: AudioSessionCoordinator()
        )
    }

    /// Designated init: inject collaborators (tests pass fakes).
    init(
        session: TuningSessionModel,
        engine: AudioInputProviding,
        detector: PitchDetecting,
        tone: TonePlaying,
        audioSession: AudioSessionConfiguring
    ) {
        self.session = session
        self.engine = engine
        self.detector = detector
        self.tone = tone
        self.audioSession = audioSession
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

    /// The app returned to the foreground. The view has just refreshed permission;
    /// we re-assert the engine so a mic that stopped in the background comes back.
    /// This is bug (c)'s fix — `.onChange(of: permission)` can't catch an
    /// *unchanged* grant, so nothing else would revive the engine.
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
    /// mic). Turning OFF resets the targeted session — bug (b)'s fix: while
    /// chromatic was on the session was bypassed, so without this it would return
    /// holding stale latches/zone. `session.reset()` keeps the chosen
    /// instrument/tuning/capo and only clears the live progress.
    func setChromatic(_ on: Bool, permission: MicPermissionState) {
        isChromaticMode = on
        if on {
            if isToneMode { setToneMode(false, permission: permission) }
        } else {
            session.reset()
        }
    }

    // MARK: - Peg taps

    /// Route a peg tap: in tone-mode play that string's target pitch (remembering
    /// the index for the highlight); otherwise lock onto it for tuning.
    func handlePegTap(_ index: Int) {
        guard session.targets.indices.contains(index) else { return }
        if isToneMode {
            tonePegIndex = index
            tone.play(frequencyHz: session.targets[index].frequencyHz)
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
    /// actually switched us to playback (the editor's tap-to-hear) — bug (a)'s fix.
    /// The old code restarted the mic on EVERY dismiss, even after just browsing the
    /// picker. We also leave tone-mode untouched: its playback route is deliberate.
    func onSheetDismiss(permission: MicPermissionState) {
        guard audioRoute == .playback, !isToneMode else { return }
        tone.shutdown()
        syncEngine(to: permission)
    }
}
