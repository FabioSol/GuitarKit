//
//  PitchTrackerTests.swift
//  GuitarKitTests
//
//  Tests for the whole pitch pipeline — preprocess → in-band gate → detect →
//  clarity gate → continuity → smooth → resolve — through `PitchTracker`'s
//  small interface (`process`, `reset`, `config`) with synthetic signals.
//
//  NOTE ON CADENCE: onset confirmation means a note is returned on its second
//  consecutive agreeing frame — the first frame is held as a candidate (so an
//  isolated noise accept can never reach the UI). Tests that expect a reading
//  therefore feed two buffers.
//

import XCTest
@testable import GuitarKit

@MainActor
final class PitchTrackerTests: XCTestCase {

    private let sampleRate = 44_100.0

    /// Feed the same buffer twice — two consecutive agreeing frames, the
    /// minimum a real note needs to clear onset confirmation — and return the
    /// second frame's reading.
    @discardableResult
    private func processConfirmed(_ tracker: inout PitchTracker, _ samples: [Float]) -> PitchReading? {
        _ = tracker.process(samples: samples, sampleRate: sampleRate)
        return tracker.process(samples: samples, sampleRate: sampleRate)
    }

    private var silence: [Float] { [Float](repeating: 0, count: 4_096) }

    func test_sustainedTone_readsCorrectNote() {
        var tracker = PitchTracker()
        // A3 = 220 Hz.
        let reading = processConfirmed(&tracker, Signal.sine(frequency: 220, sampleRate: sampleRate))

        XCTAssertEqual(reading?.note, Note(pitchClass: .a, octave: 3))
        XCTAssertEqual(reading?.centOffset ?? .nan, 0, accuracy: 5)
        XCTAssertGreaterThan(reading?.clarity ?? 0, 0.9)
    }

    func test_singleFrame_isHeldForConfirmation() {
        var tracker = PitchTracker()
        // One frame — a real tone, but indistinguishable (in stream terms) from
        // an isolated noise accept. It must NOT produce a reading yet.
        let reading = tracker.process(samples: Signal.sine(frequency: 220, sampleRate: sampleRate),
                                      sampleRate: sampleRate)
        XCTAssertNil(reading, "the first frame after silence is a candidate, not a reading")
    }

    func test_silence_readsNil() {
        var tracker = PitchTracker()
        XCTAssertNil(tracker.process(samples: silence, sampleRate: sampleRate))
    }

    func test_belowLevelGate_readsNil() {
        var tracker = PitchTracker()
        // A real 220 Hz tone at ~−83 dBFS — far too quiet to clear the −68 dBFS gate.
        let whisper = Signal.sine(frequency: 220, sampleRate: sampleRate, amplitude: 0.0001)
        XCTAssertNil(processConfirmed(&tracker, whisper))
    }

    func test_toneThenSilence_clearsReading() {
        var tracker = PitchTracker()
        XCTAssertNotNil(processConfirmed(&tracker, Signal.sine(frequency: 330, sampleRate: sampleRate)))
        XCTAssertNil(tracker.process(samples: silence, sampleRate: sampleRate))
    }

    func test_noteAfterSilence_startsFresh_notBlended() {
        var tracker = PitchTracker()
        // A confirmed low note, a real dropout (2 silent frames), then a much
        // higher note. The reading must be the NEW note, not a value dragged
        // toward it from stale smoothing history.
        processConfirmed(&tracker, Signal.sine(frequency: 110, sampleRate: sampleRate))
        _ = tracker.process(samples: silence, sampleRate: sampleRate)
        _ = tracker.process(samples: silence, sampleRate: sampleRate)

        let reading = processConfirmed(&tracker, Signal.sine(frequency: 440, sampleRate: sampleRate))
        XCTAssertEqual(reading?.note, Note(pitchClass: .a, octave: 4),
                       "history must not bridge a silence between notes")
        XCTAssertEqual(reading?.centOffset ?? .nan, 0, accuracy: 5)
    }

    func test_reset_requiresFreshConfirmation() {
        var tracker = PitchTracker()
        let tone = Signal.sine(frequency: 440, sampleRate: sampleRate)
        processConfirmed(&tracker, tone)
        tracker.reset()
        XCTAssertNil(tracker.process(samples: tone, sampleRate: sampleRate),
                     "after a reset the next note must be confirmed again")
    }

    // MARK: - Sustain hysteresis (the decaying tail stays on screen)

    /// A 220 Hz tone at ~−70 dBFS RMS: below the −68 onset level gate, above
    /// the −74 sustain gate — the "decaying tail" regime.
    private var quietTail: [Float] {
        Signal.sine(frequency: 220, sampleRate: sampleRate, amplitude: 0.00045)
    }

    func test_quietTail_extendsATrackedNote() {
        var tracker = PitchTracker()
        // A confirmed note JUST above the onset gate (~−65 dBFS). Confirming at
        // full level would put a huge amplitude STEP at the loud→quiet buffer
        // boundary — something a real, smoothly-decaying string never does —
        // and the step's ringing in the band-pass would pollute the tail frame.
        processConfirmed(&tracker, Signal.sine(frequency: 220, sampleRate: sampleRate, amplitude: 0.0008))
        // …then the tail sinks below the ONSET gate. The sustain gates plus the
        // on-pitch condition must keep the reading alive.
        let reading = tracker.process(samples: quietTail, sampleRate: sampleRate)
        XCTAssertEqual(reading?.note, Note(pitchClass: .a, octave: 3),
                       "the tail must stay on screen past the onset level gate")
    }

    func test_quietFrames_cannotStartANote() {
        var tracker = PitchTracker()
        // The same sub-onset-level tone with NO confirmed note in progress must
        // never read — sustain gates only ever extend, they don't admit.
        XCTAssertNil(processConfirmed(&tracker, quietTail), "onset still requires the strict gates")
    }

    // MARK: - Config

    func test_referencePitch_namesNotesAgainstCalibratedA() {
        // 432 Hz is 32 cents flat of A4 at concert pitch, but exactly A4 when
        // the user has calibrated to A=432.
        let tone = Signal.sine(frequency: 432, sampleRate: sampleRate)

        var concert = PitchTracker()
        XCTAssertEqual(processConfirmed(&concert, tone)?.centOffset ?? .nan, -31.8, accuracy: 2)

        var calibrated = PitchTracker(config: PitchTrackerConfig(referencePitch: ReferencePitch(hertz: 432)))
        let reading = processConfirmed(&calibrated, tone)
        XCTAssertEqual(reading?.note, Note(pitchClass: .a, octave: 4))
        XCTAssertEqual(reading?.centOffset ?? .nan, 0, accuracy: 2)
    }

    func test_changingReferencePitch_appliesToNextReading() {
        var tracker = PitchTracker()
        let tone = Signal.sine(frequency: 432, sampleRate: sampleRate)
        processConfirmed(&tracker, tone)
        tracker.config.referencePitch = ReferencePitch(hertz: 432)
        let reading = tracker.process(samples: tone, sampleRate: sampleRate)
        XCTAssertEqual(reading?.centOffset ?? .nan, 0, accuracy: 2)
    }

    func test_bandChange_dropsTrackedNote() {
        var tracker = PitchTracker()
        let tone = Signal.sine(frequency: 220, sampleRate: sampleRate)
        processConfirmed(&tracker, tone)
        tracker.config.band = DetectionBand(minFrequencyHz: 150, maxFrequencyHz: 400,
                                            highPassHz: 150, lowPassHz: 1200)
        XCTAssertNil(tracker.process(samples: tone, sampleRate: sampleRate),
                     "a reading from the old band must not carry across a band change")
    }

    func test_reassigningSameBand_keepsTrackedNote() {
        var tracker = PitchTracker()
        let tone = Signal.sine(frequency: 220, sampleRate: sampleRate)
        processConfirmed(&tracker, tone)
        tracker.config.band = .full          // unchanged → no-op
        XCTAssertNotNil(tracker.process(samples: tone, sampleRate: sampleRate))
    }

    // MARK: - Harmonic check

    /// Standard guitar, as targeted mode would configure it.
    private var guitarBand: DetectionBand { DetectionBand.around(lowestHz: 82.41, highestHz: 329.63)! }

    func test_harmonicCheck_blocksAChord() {
        // Two notes at once (A2 + D3) are periodic enough to pass the clarity
        // gate, but don't look like ONE harmonic source.
        let chord = Signal.mix(
            Signal.harmonicTone(fundamental: 110, harmonicAmplitudes: [0.3, 0.15, 0.1], sampleRate: sampleRate),
            Signal.harmonicTone(fundamental: 146.83, harmonicAmplitudes: [0.3, 0.15, 0.1], sampleRate: sampleRate))
        var tracker = PitchTracker(config: PitchTrackerConfig(band: guitarBand, harmonicGate: 0.65))
        XCTAssertNil(processConfirmed(&tracker, chord), "a chord must not start a note")
    }

    func test_harmonicCheck_letsAStringThrough() {
        var tracker = PitchTracker(config: PitchTrackerConfig(band: guitarBand, harmonicGate: 0.65))
        let reading = processConfirmed(&tracker, Signal.pluckedGuitarNote(fundamental: 110, sampleRate: sampleRate))
        XCTAssertEqual(reading?.note, Note(pitchClass: .a, octave: 2))
    }

    func test_harmonicCheck_letsAPureToneThrough() {
        // The reason this check is safe where HPS-as-detector wasn't.
        var tracker = PitchTracker(config: PitchTrackerConfig(band: guitarBand, harmonicGate: 0.65))
        let reading = processConfirmed(&tracker, Signal.sine(frequency: 196, sampleRate: sampleRate, amplitude: 0.3))
        XCTAssertEqual(reading?.note, Note(pitchClass: .g, octave: 3))
    }

    // MARK: - Probabilistic engine

    private var guitarTargets: [Double] { [82.41, 110.0, 146.83, 196.0, 246.94, 329.63] }

    func test_probabilisticEngine_readsAPluckedString() {
        var tracker = PitchTracker(config: PitchTrackerConfig(
            band: guitarBand, engine: .probabilistic, targetsHz: guitarTargets))
        let pluck = Signal.pluckedGuitarNote(fundamental: 110, sampleRate: sampleRate, count: 4_096 * 6)
        var reading: PitchReading?
        _ = tracker.process(samples: [Float](repeating: 0, count: 4_096), sampleRate: sampleRate)
        for w in 0..<6 {
            reading = tracker.process(samples: Array(pluck[w * 4_096 ..< (w + 1) * 4_096]),
                                      sampleRate: sampleRate) ?? reading
        }
        XCTAssertEqual(reading?.note, Note(pitchClass: .a, octave: 2))
        XCTAssertEqual(reading?.centOffset ?? .nan, 0, accuracy: 5)
    }

    func test_probabilisticEngine_withoutTargets_fallsBackToGated() {
        // Chromatic mode has no strings to track — it must behave exactly like
        // the gated engine (here: a sine needs two confirming frames).
        var tracker = PitchTracker(config: PitchTrackerConfig(engine: .probabilistic))
        let tone = Signal.sine(frequency: 440, sampleRate: sampleRate)
        XCTAssertNil(tracker.process(samples: tone, sampleRate: sampleRate))
        XCTAssertEqual(tracker.process(samples: tone, sampleRate: sampleRate)?.note,
                       Note(pitchClass: .a, octave: 4))
    }
}

/// The live adapter: publishes the tracker's result as observable state.
@MainActor
final class PitchDetectorTests: XCTestCase {

    func test_process_publishesReading_andResetClearsIt() {
        let detector = PitchDetector()
        let tone = Signal.sine(frequency: 440, sampleRate: 44_100)
        detector.process(samples: tone, sampleRate: 44_100)
        detector.process(samples: tone, sampleRate: 44_100)
        XCTAssertEqual(detector.reading?.note, Note(pitchClass: .a, octave: 4))

        detector.reset()
        XCTAssertNil(detector.reading)
    }
}
