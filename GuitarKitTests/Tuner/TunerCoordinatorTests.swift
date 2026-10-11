//
//  TunerCoordinatorTests.swift
//  GuitarKitTests
//
//  The Tuner's audio lifecycle, in isolation. Extracting `TunerCoordinator` out of
//  the SwiftUI view is what makes these transitions testable at all — we drive it
//  with silent FAKES (no microphone, no AVAudioEngine) and assert the right
//  collaborators were started/stopped. These tests pin the three lifecycle bugs
//  the extraction fixed:
//    (a) a sheet dismiss must NOT restart the mic unless a sheet used playback,
//    (b) leaving chromatic mode must reset the targeted session, and
//    (c) returning to the foreground must re-assert the engine.
//

import XCTest
import AVFoundation
@testable import GuitarKit

@MainActor
final class TunerCoordinatorTests: XCTestCase {

    // MARK: - Fakes

    private final class FakeAudioInput: AudioInputProviding {
        var level: Float = 0
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var isRunning = false
        func start() throws { startCount += 1; isRunning = true }
        func stop() { stopCount += 1; isRunning = false }
        func onBuffer(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {}
    }

    private final class FakeDetector: PitchDetecting {
        var reading: PitchReading?
        private(set) var attachCount = 0
        private(set) var resetCount = 0
        /// The last config applied, so tests can assert the coordinator retunes
        /// detection on tuning/mode/calibration changes.
        var config = PitchTrackerConfig()
        var onReading: ((PitchReading?) -> Void)?
        var band: DetectionBand { config.band }
        /// Simulate the live detector publishing a reading.
        func emit(_ reading: PitchReading?) { onReading?(reading) }
        func attach(to source: AudioInputProviding) { attachCount += 1 }
        func reset() { resetCount += 1 }
    }

    private final class FakeTone: TonePlaying {
        private(set) var currentFrequencyHz: Double?
        private(set) var shutdownCount = 0
        func play(frequencyHz: Double) { currentFrequencyHz = frequencyHz }
        func stop() { currentFrequencyHz = nil }
        func shutdown() { currentFrequencyHz = nil; shutdownCount += 1 }
    }

    private final class FakeAudioSession: AudioSessionConfiguring {
        private(set) var recordingCount = 0
        private(set) var playbackCount = 0
        private(set) var deactivateCount = 0
        func configureForRecording() throws { recordingCount += 1 }
        func configureForPlayback() throws { playbackCount += 1 }
        func deactivate() { deactivateCount += 1 }
    }

    // MARK: - Harness

    private struct Harness {
        let coordinator: TunerCoordinator
        let engine: FakeAudioInput
        let detector: FakeDetector
        let tone: FakeTone
        let audioSession: FakeAudioSession
    }

    private func makeHarness() -> Harness {
        let engine = FakeAudioInput()
        let detector = FakeDetector()
        let tone = FakeTone()
        let audioSession = FakeAudioSession()
        let coordinator = TunerCoordinator(
            session: TuningSessionModel(haptics: SilentHaptics()),
            engine: engine,
            detector: detector,
            tone: tone,
            audioSession: audioSession
        )
        return Harness(coordinator: coordinator, engine: engine,
                       detector: detector, tone: tone, audioSession: audioSession)
    }

    /// No-op haptics so the session model never touches the device in tests.
    private final class SilentHaptics: TuningHapticsProviding {
        func prepare() {}
        func inTune() {}
        func perfect() {}
        func stringLatched() {}
        func sessionCompleted() {}
    }

    // MARK: - Engine lifecycle

    func test_onAppear_granted_startsCaptureAndAttaches() {
        let h = makeHarness()
        h.coordinator.onAppear(permission: .granted, isPriming: false)
        XCTAssertEqual(h.engine.startCount, 1)
        XCTAssertEqual(h.detector.attachCount, 1)
        XCTAssertEqual(h.coordinator.audioRoute, .recording)
    }

    func test_onAppear_whilePriming_doesNotStart() {
        let h = makeHarness()
        h.coordinator.onAppear(permission: .undetermined, isPriming: true)
        XCTAssertEqual(h.engine.startCount, 0)
        XCTAssertEqual(h.coordinator.audioRoute, .idle)
    }

    func test_syncEngine_denied_tearsEverythingDown() {
        let h = makeHarness()
        h.coordinator.onAppear(permission: .granted, isPriming: false)
        h.coordinator.syncEngine(to: .denied)
        XCTAssertEqual(h.engine.stopCount, 1)
        XCTAssertGreaterThanOrEqual(h.detector.resetCount, 1)
        XCTAssertEqual(h.audioSession.deactivateCount, 1)
        XCTAssertEqual(h.coordinator.audioRoute, .idle)
    }

    // MARK: - Tone mode

    func test_enterToneMode_stopsMicAndSwitchesToPlayback() {
        let h = makeHarness()
        h.coordinator.onAppear(permission: .granted, isPriming: false)
        h.coordinator.setToneMode(true, permission: .granted)
        XCTAssertTrue(h.coordinator.isToneMode)
        XCTAssertEqual(h.engine.stopCount, 1)
        XCTAssertEqual(h.audioSession.playbackCount, 1)
        XCTAssertEqual(h.coordinator.audioRoute, .playback)
    }

    func test_leaveToneMode_resumesCapture() {
        let h = makeHarness()
        h.coordinator.onAppear(permission: .granted, isPriming: false)
        h.coordinator.setToneMode(true, permission: .granted)
        h.coordinator.setToneMode(false, permission: .granted)
        XCTAssertFalse(h.coordinator.isToneMode)
        XCTAssertEqual(h.tone.shutdownCount, 1)
        XCTAssertEqual(h.engine.startCount, 2)   // initial + resume
        XCTAssertEqual(h.coordinator.audioRoute, .recording)
    }

    // MARK: - Peg taps

    func test_pegTap_inToneMode_playsTargetAndHighlights() {
        let h = makeHarness()
        h.coordinator.setToneMode(true, permission: .granted)
        h.coordinator.handlePegTap(0)
        XCTAssertNotNil(h.tone.currentFrequencyHz)
        XCTAssertEqual(h.coordinator.tonePegIndex, 0)
        XCTAssertEqual(h.coordinator.playingStringIndex, 0)
    }

    func test_pegTap_inTargetedMode_locksString() {
        let h = makeHarness()
        h.coordinator.handlePegTap(2)
        XCTAssertNil(h.tone.currentFrequencyHz)          // no tone played
        XCTAssertEqual(h.coordinator.session.activeStringIndex, 2)
    }

    // MARK: - Bug (a): sheet dismiss must not gratuitously restart the mic

    func test_sheetDismiss_afterBrowsingPicker_doesNotRestartMic() {
        let h = makeHarness()
        h.coordinator.onAppear(permission: .granted, isPriming: false)  // start #1, route recording
        // User just opened and closed the picker — no playback ever engaged.
        h.coordinator.onSheetDismiss(permission: .granted)
        XCTAssertEqual(h.engine.startCount, 1, "the mic should not be restarted")
        XCTAssertEqual(h.tone.shutdownCount, 0)
        XCTAssertEqual(h.coordinator.audioRoute, .recording)
    }

    func test_sheetDismiss_afterHearingNote_restoresRecording() {
        let h = makeHarness()
        h.coordinator.onAppear(permission: .granted, isPriming: false)  // start #1
        // The editor's tap-to-hear switched us to playback…
        h.coordinator.playHearNote(frequencyHz: 440)
        XCTAssertEqual(h.coordinator.audioRoute, .playback)
        // …so dismissing must restore recording.
        h.coordinator.onSheetDismiss(permission: .granted)
        XCTAssertEqual(h.tone.shutdownCount, 1)
        XCTAssertEqual(h.engine.startCount, 2)
        XCTAssertEqual(h.coordinator.audioRoute, .recording)
    }

    // MARK: - Bug (b): leaving chromatic resets the targeted session

    func test_leavingChromatic_resetsTargetedSession() {
        let h = makeHarness()
        h.coordinator.session.lock(toStringIndex: 2)
        XCTAssertEqual(h.coordinator.session.activeStringIndex, 2)

        h.coordinator.setChromatic(true, permission: .granted)
        h.coordinator.setChromatic(false, permission: .granted)

        XCTAssertNil(h.coordinator.session.activeStringIndex,
                     "leaving chromatic mode should reset the stale targeted session")
    }

    func test_enteringChromatic_forcesToneModeOff() {
        let h = makeHarness()
        h.coordinator.setToneMode(true, permission: .granted)
        h.coordinator.setChromatic(true, permission: .granted)
        XCTAssertTrue(h.coordinator.isChromaticMode)
        XCTAssertFalse(h.coordinator.isToneMode, "chromatic needs the mic, so tone-mode must turn off")
    }

    // MARK: - Bug (c): returning to foreground re-asserts the engine

    func test_onBecameActive_granted_reasserttsEngine() {
        let h = makeHarness()
        h.coordinator.onAppear(permission: .granted, isPriming: false)   // start #1
        // Simulate the OS stopping capture while backgrounded.
        h.engine.stop()
        XCTAssertFalse(h.engine.isRunning)

        h.coordinator.onBecameActive(permission: .granted, isPriming: false)
        XCTAssertTrue(h.engine.isRunning, "the engine should be revived on return to foreground")
        XCTAssertEqual(h.engine.startCount, 2)
    }

    func test_onBecameActive_whileInToneMode_doesNotTouchMic() {
        let h = makeHarness()
        h.coordinator.setToneMode(true, permission: .granted)
        let startsBefore = h.engine.startCount
        h.coordinator.onBecameActive(permission: .granted, isPriming: false)
        XCTAssertEqual(h.engine.startCount, startsBefore, "tone-mode keeps the mic off")
    }

    func test_onBecameActive_whilePriming_doesNothing() {
        let h = makeHarness()
        h.coordinator.onBecameActive(permission: .undetermined, isPriming: true)
        XCTAssertEqual(h.engine.startCount, 0)
    }

    // MARK: - Detector → session gating

    func test_handleDetectorReading_ignoredInChromaticMode() {
        let h = makeHarness()
        h.coordinator.session.lock(toStringIndex: 1)
        h.coordinator.setChromatic(true, permission: .granted)
        // A reading arriving in chromatic mode must not feed the targeted session.
        h.coordinator.handleDetectorReading(
            PitchReading(frequency: 110, note: Note(pitchClass: .a, octave: 2), centOffset: 0, clarity: 1)
        )
        // The session was reset on entering chromatic? No — only on LEAVING. Here we
        // just assert the reading didn't drive it to a complete/odd state by
        // confirming it stays on the locked string (ingest was skipped).
        XCTAssertEqual(h.coordinator.session.activeStringIndex, 1)
    }

    // MARK: - Detection band (the tuning-derived prior)

    /// The band the default session (standard guitar, E2…E4) should produce.
    private func standardGuitarBand() -> DetectionBand? {
        DetectionBand.around(targets: TuningSessionModel(haptics: SilentHaptics()).targets)
    }

    func test_init_appliesTuningBand_notFullRange() {
        let h = makeHarness()
        XCTAssertEqual(h.detector.band, standardGuitarBand(),
                       "targeted mode should constrain detection to the tuning's band")
        XCTAssertNotEqual(h.detector.band, .full)
        // Sanity-check the low edge: E2 (82.41 Hz) − 5 semitones ≈ 61.7 Hz.
        XCTAssertEqual(h.detector.band.minFrequencyHz, 61.74, accuracy: 0.05)
    }

    func test_chromaticMode_widensToFullBand_andRestoresOnExit() {
        let h = makeHarness()
        h.coordinator.setChromatic(true, permission: .granted)
        XCTAssertEqual(h.detector.band, .full, "chromatic must hear any pitch")

        h.coordinator.setChromatic(false, permission: .granted)
        XCTAssertEqual(h.detector.band, standardGuitarBand(),
                       "leaving chromatic should restore the tuning band")
    }

    func test_editorCapture_widensToFullBand_andSheetDismissRestores() {
        let h = makeHarness()
        h.coordinator.onEditorOpened()
        XCTAssertEqual(h.detector.band, .full, "capture-by-playing must hear any pitch")

        h.coordinator.onSheetDismiss(permission: .granted)
        XCTAssertEqual(h.detector.band, standardGuitarBand(),
                       "dismissing the editor should restore the tuning band")
    }

    func test_capoChange_retunesBand() {
        let h = makeHarness()
        let openBand = h.detector.band
        h.coordinator.session.incrementCapo()
        // Capo 1 shifts every target up a semitone, so the whole band rises.
        XCTAssertGreaterThan(h.detector.band.minFrequencyHz, openBand.minFrequencyHz)
        XCTAssertGreaterThan(h.detector.band.maxFrequencyHz, openBand.maxFrequencyHz)
    }

    // MARK: - Leaving and returning to the Tuner

    func test_onLeave_stopsListening_butKeepsTheSession() {
        let h = makeHarness()
        h.coordinator.onAppear(permission: .granted, isPriming: false)
        h.coordinator.session.incrementCapo()
        h.coordinator.onLeave()
        XCTAssertEqual(h.engine.stopCount, 1, "the mic must stop when the player leaves the Tuner")
        XCTAssertFalse(h.engine.isRunning)
        XCTAssertEqual(h.coordinator.session.capo.fret, 1, "tuning progress survives the trip")

        h.coordinator.onAppear(permission: .granted, isPriming: false)
        XCTAssertTrue(h.engine.isRunning, "coming back starts listening again")
    }

    func test_onLeave_endsToneMode() {
        let h = makeHarness()
        h.coordinator.setToneMode(true, permission: .granted)
        h.coordinator.onLeave()
        XCTAssertFalse(h.coordinator.isToneMode)
        XCTAssertGreaterThan(h.tone.shutdownCount, 0)
    }

    func test_selectionIsRestoredOnlyOnce() {
        let h = makeHarness()
        h.coordinator.restoreSelectionOnce()
        h.coordinator.session.lock(toStringIndex: 1)
        // A second appear must NOT rebuild the session — a rebuild clears the
        // lock (and any strings already latched).
        h.coordinator.restoreSelectionOnce()
        XCTAssertTrue(h.coordinator.session.isManuallyLocked)
    }

    // MARK: - Selection: one writer, one truth

    func test_select_updatesTheSharedSelection_andTheSession() {
        let h = makeHarness()
        let bass = InstrumentLibrary.instrument(id: "bass-4")!
        let tuning = bass.tunings.last!
        h.coordinator.select(instrument: bass, tuning: tuning)
        XCTAssertEqual(h.coordinator.selection.currentInstrument.id, "bass-4",
                       "Chords/Scales read the same selection")
        XCTAssertEqual(h.coordinator.selection.currentTuning, tuning)
        XCTAssertEqual(h.coordinator.session.currentInstrument.id, "bass-4")
        XCTAssertEqual(h.coordinator.session.currentTuning, tuning)
    }

    func test_savingACustomTuning_selectsIt_andTheSelectionResolvesIt() {
        let h = makeHarness()
        let open = h.coordinator.session.currentTuning.strings
        let custom = Tuning(name: "My Open", category: .alternate, strings: open)
        h.coordinator.saveCustomTuning(custom)
        XCTAssertEqual(h.coordinator.session.currentTuning.name, "My Open")
        XCTAssertEqual(h.coordinator.selection.currentTuning.name, "My Open",
                       "a custom tuning must resolve through the shared selection")
        h.coordinator.deleteCustomTuning(named: "My Open", for: h.coordinator.session.currentInstrument)
        XCTAssertTrue(h.coordinator.customTunings
            .tunings(forInstrumentID: h.coordinator.session.currentInstrument.id).isEmpty)
    }

    // MARK: - Detector → session (no view in between)

    func test_detectorReadings_reachTheSession_directly() {
        let h = makeHarness()
        let a2 = PitchReading(frequency: 110, note: Note(pitchClass: .a, octave: 2),
                              centOffset: 0, clarity: 0.9)
        h.detector.emit(a2)
        XCTAssertEqual(h.coordinator.session.activeStringIndex, 1, "A2 is string 1 of standard guitar")
    }

    // MARK: - Harmonic check (targeted mode only)

    func test_targetedMode_turnsHarmonicCheckOn() {
        let h = makeHarness()
        XCTAssertEqual(h.detector.config.harmonicGate, PitchTrackerConfig.targetedModeHarmonicGate)
        XCTAssertGreaterThan(h.detector.config.harmonicGate, 0)
    }

    func test_chromaticAndEditorCapture_turnHarmonicCheckOff_andBack() {
        let h = makeHarness()
        h.coordinator.setChromatic(true, permission: .granted)
        XCTAssertEqual(h.detector.config.harmonicGate, 0, "chromatic must hear any sound")
        h.coordinator.setChromatic(false, permission: .granted)
        XCTAssertEqual(h.detector.config.harmonicGate, PitchTrackerConfig.targetedModeHarmonicGate)

        h.coordinator.onEditorOpened()
        XCTAssertEqual(h.detector.config.harmonicGate, 0, "capture-by-playing must hear any sound")
        h.coordinator.onSheetDismiss(permission: .granted)
        XCTAssertEqual(h.detector.config.harmonicGate, PitchTrackerConfig.targetedModeHarmonicGate)
    }

    func test_targetedMode_passesStringTargets_chromaticClearsThem() {
        // The probabilistic engine tracks the tuning's strings; chromatic mode
        // has none (it falls back to the gated engine).
        let h = makeHarness()
        XCTAssertEqual(h.detector.config.targetsHz, h.coordinator.session.targets.map(\.frequencyHz))
        XCTAssertEqual(h.detector.config.targetsHz.count, 6)
        h.coordinator.setChromatic(true, permission: .granted)
        XCTAssertTrue(h.detector.config.targetsHz.isEmpty)
        h.coordinator.setChromatic(false, permission: .granted)
        XCTAssertEqual(h.detector.config.targetsHz.count, 6)
    }

    func test_changedTargetedGate_survivesAModeRoundTrip() {
        // The Tuner Lab sets the gate on the coordinator, so a chromatic
        // round-trip restores the Lab's value, not the default.
        let h = makeHarness()
        h.coordinator.targetedHarmonicGate = 0.5
        h.coordinator.setChromatic(true, permission: .granted)
        h.coordinator.setChromatic(false, permission: .granted)
        XCTAssertEqual(h.detector.config.harmonicGate, 0.5)
    }

    // MARK: - Reference pitch (chromatic names use the user's calibration)

    func test_init_appliesSessionReferencePitch() {
        let h = makeHarness()
        XCTAssertEqual(h.detector.config.referencePitch, .standard)
    }

    func test_recalibration_reachesDetector() {
        let h = makeHarness()
        h.coordinator.session.reconfigure(referencePitch: ReferencePitch(hertz: 432),
                                          tolerance: .standard)
        XCTAssertEqual(h.detector.config.referencePitch.hertz, 432,
                       "the chromatic readout must name notes against the calibrated A4")
    }
}
