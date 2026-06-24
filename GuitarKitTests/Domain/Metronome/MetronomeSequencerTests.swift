//
//  MetronomeSequencerTests.swift
//  GuitarKitTests
//
//  Tests for the pure metronome timing math. The behaviors that matter: the beat
//  spacing is correct, beats are EVENLY spaced with no accumulating drift over
//  thousands of beats, and bad inputs are handled.
//

import XCTest
@testable import GuitarKit

final class MetronomeSequencerTests: XCTestCase {

    private let sampleRate = 44_100.0

    // MARK: - Beat spacing

    func test_samplesPerBeat_120bpm_is22050() {
        // 60 / 120 = 0.5 s per beat; 0.5 × 44100 = 22050 samples.
        XCTAssertEqual(MetronomeSequencer.samplesPerBeat(bpm: 120, sampleRate: sampleRate),
                       22_050, accuracy: 0.0001)
    }

    func test_samplesPerBeat_60bpm_isOneSecond() {
        XCTAssertEqual(MetronomeSequencer.samplesPerBeat(bpm: 60, sampleRate: sampleRate),
                       44_100, accuracy: 0.0001)
    }

    func test_samplesPerBeat_invalidInputs_areZero() {
        XCTAssertEqual(MetronomeSequencer.samplesPerBeat(bpm: 0, sampleRate: sampleRate), 0)
        XCTAssertEqual(MetronomeSequencer.samplesPerBeat(bpm: 120, sampleRate: 0), 0)
        XCTAssertEqual(MetronomeSequencer.samplesPerBeat(bpm: -5, sampleRate: sampleRate), 0)
    }

    // MARK: - Beat offsets

    func test_beatZero_isSampleZero() {
        XCTAssertEqual(MetronomeSequencer.sampleOffset(ofBeat: 0, bpm: 130, sampleRate: sampleRate), 0)
    }

    func test_beatOffset_isBeatTimesSpacing() {
        // Beat 4 at 120 BPM = 4 × 22050 = 88200.
        XCTAssertEqual(MetronomeSequencer.sampleOffset(ofBeat: 4, bpm: 120, sampleRate: sampleRate),
                       88_200)
    }

    func test_negativeBeat_clampsToZero() {
        XCTAssertEqual(MetronomeSequencer.sampleOffset(ofBeat: -3, bpm: 120, sampleRate: sampleRate), 0)
    }

    // MARK: - Drift-free over many beats (the important one)

    func test_spacing_neverDrifts_overThousandsOfBeats() {
        // At a tempo with a FRACTIONAL samples-per-beat (130 BPM → 20353.846…),
        // a naive "add a rounded step each beat" would accumulate error. Because
        // each offset is computed independently from beat 0, consecutive gaps must
        // stay within ±1 sample of the exact spacing even at beat ~10000.
        let bpm = 130.0
        let spacing = MetronomeSequencer.samplesPerBeat(bpm: bpm, sampleRate: sampleRate)
        for beat in 1...10_000 {
            let gap = MetronomeSequencer.sampleOffset(ofBeat: beat, bpm: bpm, sampleRate: sampleRate)
                    - MetronomeSequencer.sampleOffset(ofBeat: beat - 1, bpm: bpm, sampleRate: sampleRate)
            XCTAssertEqual(Double(gap), spacing, accuracy: 1.0,
                           "beat \(beat) gap drifted")
        }
    }

    // MARK: - Pre-scheduling helper

    func test_offsets_returnsConsecutiveBeats() {
        let offsets = MetronomeSequencer.offsets(fromBeat: 4, count: 3, bpm: 120, sampleRate: sampleRate)
        XCTAssertEqual(offsets, [88_200, 110_250, 132_300])  // beats 4,5,6 × 22050
    }

    func test_offsets_nonPositiveCount_isEmpty() {
        XCTAssertTrue(MetronomeSequencer.offsets(fromBeat: 0, count: 0, bpm: 120, sampleRate: sampleRate).isEmpty)
    }
}
