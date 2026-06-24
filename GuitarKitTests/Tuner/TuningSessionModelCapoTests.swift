//
//  TuningSessionModelCapoTests.swift
//  GuitarKitTests
//
//  Regression coverage for the capo mutators on `TuningSessionModel` — in
//  particular the `decrementCapo()` added so the VoiceOver "decrement" swipe steps
//  the capo down by ONE fret instead of jumping straight to "no capo" (audit P2).
//  The pure 0...12 clamping lives in `Capo` (covered by `CapoTests`); here we pin
//  the model wrapper's behavior: increment/decrement step by one, both clamp, and
//  the string targets transpose with the capo.
//

import XCTest
@testable import GuitarKit

@MainActor
final class TuningSessionModelCapoTests: XCTestCase {

    func test_incrementCapo_raisesByOneFret() {
        let model = TuningSessionModel()
        XCTAssertEqual(model.capo.fret, 0)
        model.incrementCapo()
        XCTAssertEqual(model.capo.fret, 1)
        model.incrementCapo()
        XCTAssertEqual(model.capo.fret, 2)
    }

    func test_decrementCapo_lowersByOneFret() {
        let model = TuningSessionModel()
        model.incrementCapo()
        model.incrementCapo()
        model.incrementCapo()           // fret 3
        model.decrementCapo()
        XCTAssertEqual(model.capo.fret, 2, "decrement should step DOWN by exactly one, not reset")
    }

    func test_decrementCapo_atZero_staysAtZero() {
        let model = TuningSessionModel()
        model.decrementCapo()
        XCTAssertEqual(model.capo.fret, 0, "decrement at fret 0 is a harmless clamped no-op")
    }

    func test_decrementCapo_isNotAReset() {
        // The whole point of the fix: a single decrement on an engaged capo must
        // NOT collapse to fret 0 the way the old VoiceOver mapping did.
        let model = TuningSessionModel()
        for _ in 0..<5 { model.incrementCapo() } // fret 5
        model.decrementCapo()
        XCTAssertEqual(model.capo.fret, 4)
        XCTAssertTrue(model.capo.isEngaged)
    }

    func test_capoChange_transposesTargets() {
        let model = TuningSessionModel()
        guard let openLow = model.targets.first?.frequencyHz else {
            return XCTFail("expected at least one string target")
        }
        model.incrementCapo()           // +1 semitone
        guard let cappedLow = model.targets.first?.frequencyHz else {
            return XCTFail("expected targets after capo change")
        }
        // One semitone up multiplies frequency by 2^(1/12) ≈ 1.0595.
        XCTAssertEqual(cappedLow / openLow, pow(2.0, 1.0 / 12.0), accuracy: 0.001)

        model.decrementCapo()           // back to no capo
        XCTAssertEqual(model.targets.first?.frequencyHz ?? 0, openLow, accuracy: 0.001)
    }
}
