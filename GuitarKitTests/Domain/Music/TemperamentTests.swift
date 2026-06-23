//
//  TemperamentTests.swift
//  GuitarKitTests
//
//  Behavioral tests proving equal temperament applies no sweetening, and that
//  a sweetened profile's per-string offsets flow through to target frequencies.
//

import XCTest
@testable import GuitarKit

final class TemperamentTests: XCTestCase {

    private let tolerance = 0.01

    // Standard 6-string guitar, low-to-high: E2 A2 D3 G3 B3 E4.
    private let standardGuitar: [Note] = [
        Note(pitchClass: .e, octave: 2),
        Note(pitchClass: .a, octave: 2),
        Note(pitchClass: .d, octave: 3),
        Note(pitchClass: .g, octave: 3),
        Note(pitchClass: .b, octave: 3),
        Note(pitchClass: .e, octave: 4),
    ]

    // MARK: Equal temperament — zero offsets everywhere

    func test_equalTemperament_returnsZeroForEveryString() {
        let eq = EqualTemperament()
        for index in 0..<6 {
            XCTAssertEqual(eq.centOffset(forStringIndex: index, stringCount: 6), 0)
        }
    }

    func test_equalTemperament_targetsMatchPlainFrequencies() {
        // Through the calculator, every string's target equals the bare formula.
        let calc = PitchCalculator(temperament: EqualTemperament())
        let targets = calc.targets(for: standardGuitar)
        for (index, note) in standardGuitar.enumerated() {
            XCTAssertEqual(targets[index].frequencyHz,
                           calc.frequency(of: note),
                           accuracy: tolerance)
        }
    }

    // MARK: Sweetened temperament — offsets flow through to frequency

    func test_sweetened_appliesPerStringOffsets() {
        // Nudge the G string (index 3) flat by 2 cents, B string (index 4) flat
        // by 1 cent; all others 0 — a plausible acoustic sweetening.
        let offsets: [Double] = [0, 0, 0, -2, -1, 0]
        let sweetened = SweetenedTemperament(offsets: offsets)
        let calc = PitchCalculator(temperament: sweetened)

        let targets = calc.targets(for: standardGuitar)

        // The G string target should be flat of its equal-tempered frequency.
        let plainG = PitchCalculator().frequency(of: standardGuitar[3])
        XCTAssertLessThan(targets[3].frequencyHz, plainG)

        // And exactly -2 cents flat — verify by re-deriving with the offset.
        let expectedG = PitchCalculator().frequency(of: standardGuitar[3], centOffset: -2)
        XCTAssertEqual(targets[3].frequencyHz, expectedG, accuracy: tolerance)

        // Unsweetened strings (index 0) are unchanged.
        let plainE = PitchCalculator().frequency(of: standardGuitar[0])
        XCTAssertEqual(targets[0].frequencyHz, plainE, accuracy: tolerance)
    }

    func test_sweetened_outOfRangeStringReturnsZeroOffset() {
        // A 6-entry profile asked about a 7th string returns 0 (no crash).
        let sweetened = SweetenedTemperament(offsets: [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(sweetened.centOffset(forStringIndex: 6, stringCount: 7), 0)
    }

    func test_temperament_isSwappableThroughProtocol() {
        // The calculator stores `any Temperament` — same call site, different
        // behavior. This is the polymorphism the PRD relies on.
        let eqCalc = PitchCalculator(temperament: EqualTemperament())
        let swCalc = PitchCalculator(temperament: SweetenedTemperament(offsets: [10, 10, 10, 10, 10, 10]))
        let eqTargets = eqCalc.targets(for: standardGuitar)
        let swTargets = swCalc.targets(for: standardGuitar)
        // Sweetened (+10c) must be sharper than equal on every string.
        for i in 0..<6 {
            XCTAssertGreaterThan(swTargets[i].frequencyHz, eqTargets[i].frequencyHz)
        }
    }
}
