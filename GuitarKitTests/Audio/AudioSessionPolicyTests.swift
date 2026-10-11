//
//  AudioSessionPolicyTests.swift
//  GuitarKitTests
//
//  The app's one audio-session owner decides the session from every tool's
//  current need. These pin that decision — especially the case that used to
//  break: stopping the metronome while the Tuner listens.
//

import XCTest
@testable import GuitarKit

final class AudioSessionPolicyTests: XCTestCase {

    private func policy(_ needs: [AudioSessionCoordinator.Need],
                        current: AudioSessionCoordinator.Configuration? = nil) -> AudioSessionCoordinator.Configuration? {
        AudioSessionCoordinator.configuration(for: needs, current: current)
    }

    func test_nobodyNeedsAudio_deactivates() {
        XCTAssertNil(policy([], current: .playAndRecord))
    }

    func test_anyoneRecording_playsAndRecords() {
        XCTAssertEqual(policy([.recording]), .playAndRecord)
        XCTAssertEqual(policy([.playback, .recording], current: .playback), .playAndRecord,
                       "the Tuner's mic starts while the metronome plays")
    }

    func test_onlyPlayback_usesPlayback() {
        XCTAssertEqual(policy([.playback]), .playback)
    }

    func test_metronomeStops_whileTunerListens_sessionStaysUp() {
        // Tuner recording + metronome playing → the metronome stops.
        XCTAssertEqual(policy([.recording], current: .playAndRecord), .playAndRecord,
                       "stopping the metronome must not touch the Tuner's mic")
    }

    func test_tunerLeaves_whileMetronomePlays_noReconfiguration() {
        // Play-and-record can already play — switching to .playback would
        // reconfigure the metronome's running engine for nothing.
        XCTAssertEqual(policy([.playback], current: .playAndRecord), .playAndRecord)
    }
}
