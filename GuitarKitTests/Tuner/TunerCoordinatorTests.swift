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
        func process(samples: [Float], sampleRate: Double) {}
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
}
