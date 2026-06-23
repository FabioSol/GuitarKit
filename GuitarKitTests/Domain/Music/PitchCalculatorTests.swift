//
//  PitchCalculatorTests.swift
//  GuitarKitTests
//
//  Behavioral tests for frequency derivation across reference pitches,
//  temperament sweetening, and cent deviation. Public interface only.
//

import XCTest
@testable import GuitarKit

final class PitchCalculatorTests: XCTestCase {

    /// Floating-point math is never exact, so we compare with a tolerance.
    /// 0.01 Hz is far tighter than any audible difference yet loose enough to
    /// absorb rounding in `pow`/`log2`.
    private let tolerance = 0.01

    // MARK: Reference pitch — A4 lands exactly on the reference

    func test_a4_equalsReferenceFrequency_at440() {
        let calc = PitchCalculator(referenceA: ReferencePitch(hertz: 440))
        let a4 = Note(pitchClass: .a, octave: 4)
        XCTAssertEqual(calc.frequency(of: a4), 440, accuracy: tolerance)
    }

    func test_a4_equalsReferenceFrequency_at432() {
        let calc = PitchCalculator(referenceA: ReferencePitch(hertz: 432))
        let a4 = Note(pitchClass: .a, octave: 4)
        XCTAssertEqual(calc.frequency(of: a4), 432, accuracy: tolerance)
    }

    func test_a4_equalsReferenceFrequency_at442() {
        let calc = PitchCalculator(referenceA: ReferencePitch(hertz: 442))
        let a4 = Note(pitchClass: .a, octave: 4)
        XCTAssertEqual(calc.frequency(of: a4), 442, accuracy: tolerance)
    }

    // MARK: Known frequencies at concert pitch (textbook values)

    func test_middleC4_is261_63Hz_at440() {
        // Published equal-tempered value for middle C at A=440 is 261.63 Hz.
        let calc = PitchCalculator() // defaults to A=440, equal temperament
        let c4 = Note(pitchClass: .c, octave: 4)
        XCTAssertEqual(calc.frequency(of: c4), 261.63, accuracy: 0.01)
    }

    func test_lowGuitarE2_is82_41Hz_at440() {
        // Published equal-tempered value for low-E (E2) at A=440 is 82.41 Hz.
        let calc = PitchCalculator()
        let e2 = Note(pitchClass: .e, octave: 2)
        XCTAssertEqual(calc.frequency(of: e2), 82.41, accuracy: 0.01)
    }

    func test_octaveAboveA4_is880Hz() {
        let calc = PitchCalculator()
        let a5 = Note(pitchClass: .a, octave: 5)
        XCTAssertEqual(calc.frequency(of: a5), 880, accuracy: tolerance)
    }

    // MARK: Reference pitch scales everything proportionally

    func test_referencePitch_scalesAllNotesProportionally() {
        // At A=432 every note should be 432/440 of its 440 frequency.
        let calc440 = PitchCalculator(referenceA: ReferencePitch(hertz: 440))
        let calc432 = PitchCalculator(referenceA: ReferencePitch(hertz: 432))
        let c4 = Note(pitchClass: .c, octave: 4)
        let expected = calc440.frequency(of: c4) * (432.0 / 440.0)
        XCTAssertEqual(calc432.frequency(of: c4), expected, accuracy: tolerance)
    }

    // MARK: Cent offset (sweetening) shifts frequency

    func test_centOffset_of100_raisesBySemitone() {
        // +100 cents = exactly one equal-tempered semitone.
        let calc = PitchCalculator()
        let a4 = Note(pitchClass: .a, octave: 4)
        let aSharp4 = Note(pitchClass: .aSharp, octave: 4)
        let raised = calc.frequency(of: a4, centOffset: 100)
        XCTAssertEqual(raised, calc.frequency(of: aSharp4), accuracy: tolerance)
    }

    func test_centOffset_of0_isNoChange() {
        let calc = PitchCalculator()
        let g3 = Note(pitchClass: .g, octave: 3)
        XCTAssertEqual(calc.frequency(of: g3, centOffset: 0),
                       calc.frequency(of: g3), accuracy: tolerance)
    }

    // MARK: Cent deviation (detected vs target)

    func test_cents_betweenOctave_is1200() {
        XCTAssertEqual(PitchCalculator.cents(from: 880, to: 440), 1200, accuracy: 0.001)
    }

    func test_cents_sharpIsPositive_flatIsNegative() {
        XCTAssertGreaterThan(PitchCalculator.cents(from: 445, to: 440), 0)
        XCTAssertLessThan(PitchCalculator.cents(from: 435, to: 440), 0)
    }

    func test_cents_inTune_isZero() {
        XCTAssertEqual(PitchCalculator.cents(from: 440, to: 440), 0, accuracy: 0.0001)
    }

    func test_cents_safeForSilence_returnsZero() {
        // Detector reports 0 Hz during silence; must not crash or return NaN.
        XCTAssertEqual(PitchCalculator.cents(from: 0, to: 440), 0)
    }
}
