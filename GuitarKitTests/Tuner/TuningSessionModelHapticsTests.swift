//
//  TuningSessionModelHapticsTests.swift
//  GuitarKitTests
//
//  `TuningSessionModel` is mostly thin plumbing over the pure `TuningSession`, but
//  it owns one piece of real behaviour worth pinning: it fires HAPTICS on the right
//  EDGES — once when a string arrives in tune, once when it latches, and once when
//  the whole session completes — never every frame. We drive it with an injected
//  controllable clock and a SPY haptics so we can assert the exact call counts with
//  no device.
//

import XCTest
@testable import GuitarKit

@MainActor
final class TuningSessionModelHapticsTests: XCTestCase {

    /// Counts every haptic call so we can assert edges fire exactly once.
    private final class SpyHaptics: TuningHapticsProviding {
        var inTuneCount = 0, perfectCount = 0, latchedCount = 0, completedCount = 0
        func prepare() {}
        func inTune()   { inTuneCount += 1 }
        func perfect()  { perfectCount += 1 }
        func stringLatched() { latchedCount += 1 }
        func sessionCompleted() { completedCount += 1 }
    }

    private final class FakeClock {
        var t: TimeInterval = 0
        func now() -> TimeInterval { t }
    }

    private let calc = PitchCalculator()

    /// Frequency of a note, optionally detuned by `centsOff` cents.
    private func freq(_ pc: PitchClass, _ oct: Int, centsOff: Double = 0) -> Double {
        calc.frequency(of: Note(pitchClass: pc, octave: oct)) * pow(2.0, centsOff / 1200.0)
    }

    private func reading(_ hz: Double) -> PitchReading {
        PitchReading(frequency: hz, note: Note.from(midiNumber: 69), centOffset: 0, clarity: 1)
    }

    private func make() -> (TuningSessionModel, FakeClock, SpyHaptics) {
        let clock = FakeClock()
        let spy = SpyHaptics()
        let model = TuningSessionModel(now: clock.now, haptics: spy)
        return (model, clock, spy)
    }

    // MARK: - "Entered in tune" fires once on the edge

    func test_arrivingInTune_firesInTuneHapticOnceOnTheEdge() {
        let (model, clock, spy) = make()
        // Low E, +2¢: inside the in-tune window (≤3¢) but outside the perfect
        // window (≤1¢), so it's the .inTune zone, not .perfect.
        let e = reading(freq(.e, 2, centsOff: 2))

        clock.t = 0.0; model.ingest(e)     // flat/none → inTune  : edge, fires
        clock.t = 0.1; model.ingest(e)     // inTune → inTune     : no edge
        clock.t = 0.2; model.ingest(e)     // still no edge

        XCTAssertEqual(spy.inTuneCount, 1, "the in-tune tick should fire once, on arrival — not every frame")
    }

    func test_deadOnPitch_firesPerfectNotInTune() {
        let (model, clock, spy) = make()
        clock.t = 0.0; model.ingest(reading(freq(.e, 2)))   // 0¢ → .perfect
        XCTAssertEqual(spy.perfectCount, 1)
        XCTAssertEqual(spy.inTuneCount, 0)
    }

    // MARK: - Latch fires once after the hold

    func test_holdingInTune_latchesAndFiresLatchHapticOnce() {
        let (model, clock, spy) = make()
        let e = reading(freq(.e, 2))
        clock.t = 0.0; model.ingest(e)     // arrive in tune
        clock.t = 1.0; model.ingest(e)     // held past the 0.7s hold → latches
        XCTAssertEqual(spy.latchedCount, 1, "latch should fire exactly once when the hold completes")
        XCTAssertTrue(model.isLatched(0), "the low-E string should be latched")
    }

    // MARK: - Completion fires once when every string latches

    func test_latchingEveryString_firesCompletionOnce() {
        let (model, clock, spy) = make()
        // Standard guitar, low → high. Hold each in tune long enough to latch.
        let notes: [(PitchClass, Int)] = [(.e, 2), (.a, 2), (.d, 3), (.g, 3), (.b, 3), (.e, 4)]
        for (i, n) in notes.enumerated() {
            let base = Double(i) * 2.0
            clock.t = base;       model.ingest(reading(freq(n.0, n.1)))
            clock.t = base + 1.0; model.ingest(reading(freq(n.0, n.1)))   // hold → latch
            clock.t = base + 1.5; model.ingest(nil)                       // release between strings
        }
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(spy.completedCount, 1, "the completion flourish should fire exactly once")
    }

    // MARK: - Haptics respect the enabled flag

    func test_disablingHaptics_silencesThem() {
        let (model, clock, spy) = make()
        model.hapticsEnabled = false
        clock.t = 0.0; model.ingest(reading(freq(.e, 2)))
        clock.t = 1.0; model.ingest(reading(freq(.e, 2)))
        XCTAssertEqual(spy.perfectCount + spy.inTuneCount + spy.latchedCount, 0,
            "no haptics should fire when the haptics toggle is off")
    }
}
