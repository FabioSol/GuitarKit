//
//  InstrumentLibraryTests.swift
//  GuitarKitTests
//
//  Behavioral tests for the built-in instrument catalogue, asserted through the
//  public interface only. Two kinds of guarantee live here:
//
//    1. CORRECTNESS of the data: the preset note sequences are exactly the real
//       instrument tunings (a typo in EADGBE would ship a wrong tuner), and the
//       string-count invariant holds (every preset of an entry shares its count).
//
//    2. CONSISTENCY between code and resources: every instrument's headstock JSON
//       exists, decodes, and has one peg per string — so the hero never draws an
//       indicator row that disagrees with the peg layout.
//

import XCTest
@testable import GuitarKit

final class InstrumentLibraryTests: XCTestCase {

    // A terse local note builder so the expected sequences read like spoken
    // notes — mirrors the private helper used inside the library itself.
    private func n(_ pitchClass: PitchClass, _ octave: Int) -> Note {
        Note(pitchClass: pitchClass, octave: octave)
    }

    // MARK: - Catalogue shape

    func test_catalogue_isNonEmpty_andDefaultIsStandardGuitar() {
        XCTAssertFalse(InstrumentLibrary.all.isEmpty)
        XCTAssertEqual(InstrumentLibrary.default.id, "guitar-6")
    }

    func test_instrumentLookup_findsByIdAndReturnsNilForUnknown() {
        XCTAssertEqual(InstrumentLibrary.instrument(id: "violin")?.name, "Violin")
        XCTAssertNil(InstrumentLibrary.instrument(id: "theremin"))
    }

    func test_everyInstrumentId_isUnique() {
        // Stable ids are persisted, so collisions would corrupt restore. A Set of
        // the ids must be the same size as the array if all are distinct.
        let ids = InstrumentLibrary.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - String-count invariant (every preset shares the entry's count)

    func test_everyTuning_sharesItsInstrumentStringCount() {
        for instrument in InstrumentLibrary.all {
            // The entry must have at least one preset to define a count.
            XCTAssertFalse(
                instrument.tunings.isEmpty,
                "\(instrument.id) has no tunings"
            )
            for tuning in instrument.tunings {
                XCTAssertEqual(
                    tuning.stringCount,
                    instrument.stringCount,
                    "\(instrument.id): preset \"\(tuning.name)\" has \(tuning.stringCount) strings, expected \(instrument.stringCount)"
                )
            }
        }
    }

    func test_stringCounts_matchTheKnownInstruments() {
        XCTAssertEqual(InstrumentLibrary.guitar6.stringCount, 6)
        XCTAssertEqual(InstrumentLibrary.guitar7.stringCount, 7)
        XCTAssertEqual(InstrumentLibrary.bass4.stringCount, 4)
        XCTAssertEqual(InstrumentLibrary.bass5.stringCount, 5)
        XCTAssertEqual(InstrumentLibrary.ukulele.stringCount, 4)
        XCTAssertEqual(InstrumentLibrary.banjo5.stringCount, 5)
        XCTAssertEqual(InstrumentLibrary.violin.stringCount, 4)
    }

    // MARK: - Specific preset note sequences

    // Helper: fetch a named preset's note array off an instrument.
    private func strings(
        of instrument: Instrument,
        preset name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Note] {
        guard let tuning = instrument.tunings.first(where: { $0.name == name }) else {
            XCTFail("missing preset \"\(name)\" on \(instrument.id)", file: file, line: line)
            return []
        }
        return tuning.strings
    }

    func test_guitarStandard_isEADGBE() {
        XCTAssertEqual(
            strings(of: InstrumentLibrary.guitar6, preset: "Standard"),
            [n(.e, 2), n(.a, 2), n(.d, 3), n(.g, 3), n(.b, 3), n(.e, 4)]
        )
    }

    func test_guitarDropD_lowersOnlyTheSixthStringToD2() {
        let standard = strings(of: InstrumentLibrary.guitar6, preset: "Standard")
        let dropD = strings(of: InstrumentLibrary.guitar6, preset: "Drop D")
        // Only the lowest string changes…
        XCTAssertEqual(dropD[0], n(.d, 2))
        // …and every other string is identical to standard tuning.
        XCTAssertEqual(Array(dropD.dropFirst()), Array(standard.dropFirst()))
    }

    func test_guitarOpenG_soundsAGChord() {
        XCTAssertEqual(
            strings(of: InstrumentLibrary.guitar6, preset: "Open G"),
            [n(.d, 2), n(.g, 2), n(.d, 3), n(.g, 3), n(.b, 3), n(.d, 4)]
        )
    }

    func test_guitarDADGAD_isCorrect() {
        XCTAssertEqual(
            strings(of: InstrumentLibrary.guitar6, preset: "DADGAD"),
            [n(.d, 2), n(.a, 2), n(.d, 3), n(.g, 3), n(.a, 3), n(.d, 4)]
        )
    }

    func test_guitarHalfStepDown_isEverythingDownOneSemitone() {
        let standard = strings(of: InstrumentLibrary.guitar6, preset: "Standard")
        let halfDown = strings(of: InstrumentLibrary.guitar6, preset: "Half-Step Down")
        // Each string's MIDI number is exactly one less than standard tuning.
        XCTAssertEqual(halfDown.count, standard.count)
        for (lowered, original) in zip(halfDown, standard) {
            XCTAssertEqual(lowered.midiNumber, original.midiNumber - 1)
        }
    }

    func test_sevenStringGuitar_isBEADGBE() {
        XCTAssertEqual(
            strings(of: InstrumentLibrary.guitar7, preset: "Standard"),
            [n(.b, 1), n(.e, 2), n(.a, 2), n(.d, 3), n(.g, 3), n(.b, 3), n(.e, 4)]
        )
    }

    func test_bassStandard_isEADG_oneOctaveBelowGuitarBottomFour() {
        XCTAssertEqual(
            strings(of: InstrumentLibrary.bass4, preset: "Standard"),
            [n(.e, 1), n(.a, 1), n(.d, 2), n(.g, 2)]
        )
    }

    func test_fiveStringBass_addsLowB0() {
        XCTAssertEqual(
            strings(of: InstrumentLibrary.bass5, preset: "Standard"),
            [n(.b, 0), n(.e, 1), n(.a, 1), n(.d, 2), n(.g, 2)]
        )
    }

    func test_ukulele_isReentrantGCEA() {
        let uke = strings(of: InstrumentLibrary.ukulele, preset: "Standard (Reentrant)")
        XCTAssertEqual(uke, [n(.g, 4), n(.c, 4), n(.e, 4), n(.a, 4)])
        // "Reentrant" means the 4th string (index 0, G4) is HIGHER than the 3rd
        // (index 1, C4) — the strings are not in ascending pitch order.
        XCTAssertGreaterThan(uke[0].midiNumber, uke[1].midiNumber)
    }

    func test_violin_isGDAE_inPerfectFifths() {
        let v = strings(of: InstrumentLibrary.violin, preset: "Standard")
        XCTAssertEqual(v, [n(.g, 3), n(.d, 4), n(.a, 4), n(.e, 5)])
        // Each open string is a perfect fifth (7 semitones) above the previous.
        for (lower, higher) in zip(v, v.dropFirst()) {
            XCTAssertEqual(higher.midiNumber - lower.midiNumber, 7)
        }
    }

    // MARK: - Oddity peg counts (banjo 5, violin 4)

    func test_banjo_hasFivePegs() {
        XCTAssertEqual(InstrumentLibrary.banjo5.stringCount, 5)
    }

    func test_violin_hasFourPegs() {
        XCTAssertEqual(InstrumentLibrary.violin.stringCount, 4)
    }

    // MARK: - Headstock JSON ↔ string-count consistency

    func test_everyInstrumentHeadstockSpec_resolvesToOnePegPerString() {
        for instrument in InstrumentLibrary.all {
            guard let spec = HeadstockSpec.load(instrument.headstockSpecName) else {
                XCTFail("missing/invalid headstock JSON \"\(instrument.headstockSpecName)\" for \(instrument.id)")
                continue
            }
            XCTAssertEqual(
                spec.pegs.count,
                instrument.stringCount,
                "\(instrument.id): headstock \"\(instrument.headstockSpecName)\" has \(spec.pegs.count) pegs, expected \(instrument.stringCount)"
            )
        }
    }

    func test_headstockPegs_areNormalizedWithinTheBox() {
        // Every peg anchor must sit inside the 0…1 head box, or the hero would
        // draw a dot off-screen.
        for instrument in InstrumentLibrary.all {
            guard let spec = HeadstockSpec.load(instrument.headstockSpecName) else { continue }
            for peg in spec.pegs {
                XCTAssertTrue((0...1).contains(peg.x), "\(instrument.id) peg x out of range: \(peg.x)")
                XCTAssertTrue((0...1).contains(peg.y), "\(instrument.id) peg y out of range: \(peg.y)")
            }
        }
    }
}
