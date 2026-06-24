//
//  SubdivisionSequencerTests.swift
//  GuitarKitTests
//
//  Tests for the subdivision ("tick") timing math added to `MetronomeSequencer`.
//  The behaviors that matter: a tick spacing is the beat spacing divided by the
//  subdivision, ticks that land on a beat agree EXACTLY with the beat math, the
//  in-between ticks are evenly placed, and — the important one — the tick offsets
//  never DRIFT over thousands of ticks even at a fractional spacing.
//

import XCTest
@testable import GuitarKit

final class SubdivisionSequencerTests: XCTestCase {

    private let sampleRate = 44_100.0

    // MARK: - Tick spacing

    func test_samplesPerTick_eighths_isHalfABeat() {
        // 120 BPM beat = 22050 samples; eighths (2 ticks) → 11025 per tick.
        XCTAssertEqual(
            MetronomeSequencer.samplesPerTick(bpm: 120, sampleRate: sampleRate, ticksPerBeat: 2),
            11_025, accuracy: 0.0001)
    }

    func test_samplesPerTick_quarter_equalsBeatSpacing() {
        // 1 tick per beat: a tick IS a beat.
        let perBeat = MetronomeSequencer.samplesPerBeat(bpm: 100, sampleRate: sampleRate)
        XCTAssertEqual(
            MetronomeSequencer.samplesPerTick(bpm: 100, sampleRate: sampleRate, ticksPerBeat: 1),
            perBeat, accuracy: 0.0001)
    }

    func test_samplesPerTick_nonPositiveTicks_treatedAsOne() {
        // A bad tick count must not divide by zero; it collapses to "1 per beat".
        let perBeat = MetronomeSequencer.samplesPerBeat(bpm: 120, sampleRate: sampleRate)
        XCTAssertEqual(
            MetronomeSequencer.samplesPerTick(bpm: 120, sampleRate: sampleRate, ticksPerBeat: 0),
            perBeat, accuracy: 0.0001)
    }

    func test_samplesPerTick_invalidTempo_isZero() {
        XCTAssertEqual(
            MetronomeSequencer.samplesPerTick(bpm: 0, sampleRate: sampleRate, ticksPerBeat: 2), 0)
    }

    // MARK: - Tick offsets

    func test_tickZero_isSampleZero() {
        XCTAssertEqual(
            MetronomeSequencer.tickOffset(ofTick: 0, bpm: 120, sampleRate: sampleRate, ticksPerBeat: 4), 0)
    }

    func test_negativeTick_clampsToZero() {
        XCTAssertEqual(
            MetronomeSequencer.tickOffset(ofTick: -2, bpm: 120, sampleRate: sampleRate, ticksPerBeat: 2), 0)
    }

    func test_eighthTicks_placeHalfwayBetweenBeats() {
        // At 120 BPM with eighths: tick 0 = 0, tick 1 = 11025 (the "and"),
        // tick 2 = 22050 (beat 1), tick 3 = 33075, tick 4 = 44100 (beat 2).
        XCTAssertEqual(MetronomeSequencer.tickOffset(ofTick: 1, bpm: 120, sampleRate: sampleRate, ticksPerBeat: 2), 11_025)
        XCTAssertEqual(MetronomeSequencer.tickOffset(ofTick: 2, bpm: 120, sampleRate: sampleRate, ticksPerBeat: 2), 22_050)
        XCTAssertEqual(MetronomeSequencer.tickOffset(ofTick: 3, bpm: 120, sampleRate: sampleRate, ticksPerBeat: 2), 33_075)
        XCTAssertEqual(MetronomeSequencer.tickOffset(ofTick: 4, bpm: 120, sampleRate: sampleRate, ticksPerBeat: 2), 44_100)
    }

    func test_ticksOnBeats_agreeWithBeatMath() {
        // Every `ticksPerBeat`-th tick must land EXACTLY where the beat math puts
        // that beat — otherwise subdivisions would smear the beat itself.
        let bpm = 137.0   // deliberately fractional spacing
        let ticksPerBeat = 3
        for beat in 0...50 {
            let beatOffset = MetronomeSequencer.sampleOffset(ofBeat: beat, bpm: bpm, sampleRate: sampleRate)
            let tickOnBeat = MetronomeSequencer.tickOffset(ofTick: beat * ticksPerBeat, bpm: bpm,
                                                           sampleRate: sampleRate, ticksPerBeat: ticksPerBeat)
            XCTAssertEqual(beatOffset, tickOnBeat, "beat \(beat) and its tick disagree")
        }
    }

    // MARK: - Drift-free over many ticks (the important one)

    func test_tickSpacing_neverDrifts_overThousandsOfTicks() {
        // A fractional samples-per-tick (triplets at 137 BPM) would accumulate
        // error if computed by stepping. Because each tick is anchored to tick 0,
        // consecutive gaps stay within ±1 sample of the exact spacing forever.
        let bpm = 137.0
        let ticksPerBeat = 3
        let spacing = MetronomeSequencer.samplesPerTick(bpm: bpm, sampleRate: sampleRate, ticksPerBeat: ticksPerBeat)
        for tick in 1...30_000 {
            let gap = MetronomeSequencer.tickOffset(ofTick: tick, bpm: bpm, sampleRate: sampleRate, ticksPerBeat: ticksPerBeat)
                    - MetronomeSequencer.tickOffset(ofTick: tick - 1, bpm: bpm, sampleRate: sampleRate, ticksPerBeat: ticksPerBeat)
            XCTAssertEqual(Double(gap), spacing, accuracy: 1.0, "tick \(tick) gap drifted")
        }
    }

    // MARK: - Pre-scheduling helper

    func test_tickOffsets_returnsConsecutiveTicks() {
        let offsets = MetronomeSequencer.tickOffsets(fromTick: 2, count: 3, bpm: 120,
                                                     sampleRate: sampleRate, ticksPerBeat: 2)
        XCTAssertEqual(offsets, [22_050, 33_075, 44_100])  // ticks 2,3,4 × 11025
    }

    func test_tickOffsets_nonPositiveCount_isEmpty() {
        XCTAssertTrue(MetronomeSequencer.tickOffsets(fromTick: 0, count: 0, bpm: 120,
                                                     sampleRate: sampleRate, ticksPerBeat: 2).isEmpty)
    }
}
