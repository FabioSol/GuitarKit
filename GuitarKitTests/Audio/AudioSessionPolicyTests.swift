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

    private func policy(_ needs: [AudioSessionCoordinator.Need]) -> AudioSessionCoordinator.Configuration? {
        AudioSessionCoordinator.configuration(for: needs)
    }

    func test_nobodyNeedsAudio_deactivates() {
        XCTAssertNil(policy([]))
    }

    func test_tunerListeningAlone_measures() {
        // The cleanest mic input for pitch detection.
        XCTAssertEqual(policy([.recording]), .measuring)
    }

    func test_tunerListening_whileMetronomePlays_keepsSpeakerLoud() {
        // Measurement mode skips the speaker's loudness processing — a playing
        // metronome got noticeably quieter. Default mode keeps it loud.
        XCTAssertEqual(policy([.recording, .playback]), .playAndRecord)
    }

    func test_metronomeStops_whileTunerListens_sessionStaysUp() {
        XCTAssertEqual(policy([.recording]), .measuring,
                       "stopping the metronome must not deactivate the Tuner's mic")
    }

    func test_tunerLeaves_whileMetronomePlays_backToPlayback() {
        // Full speaker loudness again once nothing records.
        XCTAssertEqual(policy([.playback]), .playback)
    }
}
