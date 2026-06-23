//
//  KeyTests.swift
//  GuitarKitTests — Harmony domain
//
//  Acceptance criterion: "Each key resolves to the correct signature, relative
//  minor, and seven diatonic triads." This file covers signatures and relative
//  minors (triads have their own file). We test through the public `Key` API,
//  never poking at internals.
//

import XCTest
@testable import GuitarKit

final class KeyTests: XCTestCase {

    // MARK: - Tonic spelling around the circle

    func testMajorTonicSpellings() {
        // Sharp side: C G D A E B F♯.
        XCTAssertEqual(Key.major(circlePosition: 0).tonic.name, "C")
        XCTAssertEqual(Key.major(circlePosition: 1).tonic.name, "G")
        XCTAssertEqual(Key.major(circlePosition: 2).tonic.name, "D")
        XCTAssertEqual(Key.major(circlePosition: 6).tonic.name, "F♯")
        // Flat side: F B♭ E♭ A♭ D♭ G♭.
        XCTAssertEqual(Key.major(circlePosition: -1).tonic.name, "F")
        XCTAssertEqual(Key.major(circlePosition: -2).tonic.name, "B♭")
        XCTAssertEqual(Key.major(circlePosition: -6).tonic.name, "G♭")
    }

    // MARK: - Key signatures (sharps/flats)

    func testCMajorHasNoAccidentals() {
        let c = Key.major(circlePosition: 0)
        XCTAssertEqual(c.keySignature, [])
        XCTAssertEqual(c.sharpsOrFlats, 0)
    }

    func testGMajorHasOneSharpFSharp() {
        let g = Key.major(circlePosition: 1)
        XCTAssertEqual(g.sharpsOrFlats, 1)
        XCTAssertEqual(g.keySignature.map(\.name), ["F♯"])
    }

    func testDMajorHasTwoSharpsInOrder() {
        let d = Key.major(circlePosition: 2)
        XCTAssertEqual(d.keySignature.map(\.name), ["F♯", "C♯"])
    }

    func testFMajorHasOneFlatBFlat() {
        let f = Key.major(circlePosition: -1)
        XCTAssertEqual(f.sharpsOrFlats, -1)
        XCTAssertEqual(f.keySignature.map(\.name), ["B♭"])
    }

    func testEFlatMajorHasThreeFlatsInOrder() {
        let eFlat = Key.major(circlePosition: -3)
        XCTAssertEqual(eFlat.tonic.name, "E♭")
        XCTAssertEqual(eFlat.keySignature.map(\.name), ["B♭", "E♭", "A♭"])
    }

    func testFSharpMajorHasSixSharps() {
        let fSharp = Key.major(circlePosition: 6)
        XCTAssertEqual(fSharp.sharpsOrFlats, 6)
        XCTAssertEqual(fSharp.keySignature.map(\.name),
                       ["F♯", "C♯", "G♯", "D♯", "A♯", "E♯"])
    }

    // MARK: - Relative minor / major

    func testRelativeMinorOfCMajorIsAMinor() {
        let relative = Key.major(circlePosition: 0).relative
        XCTAssertEqual(relative.mode, .minor)
        XCTAssertEqual(relative.tonic.name, "A")
        XCTAssertEqual(relative.name, "A minor")
    }

    func testRelativeMinorOfGMajorIsEMinor() {
        XCTAssertEqual(Key.major(circlePosition: 1).relative.name, "E minor")
    }

    func testRelativeMinorOfFMajorIsDMinor() {
        XCTAssertEqual(Key.major(circlePosition: -1).relative.name, "D minor")
    }

    func testRelativeMajorOfAMinorIsCMajor() {
        // A minor (built at signature position 0) ↔ C major.
        let aMinor = Key.minor(circlePosition: 0)
        XCTAssertEqual(aMinor.tonic.name, "A")
        XCTAssertEqual(aMinor.relative.name, "C major")
    }

    func testMinorKeySharesItsRelativeMajorsSignature() {
        // E minor shares G major's signature: one sharp, F♯.
        let eMinor = Key.minor(circlePosition: 1)
        XCTAssertEqual(eMinor.tonic.name, "E")
        XCTAssertEqual(eMinor.sharpsOrFlats, 1)
        XCTAssertEqual(eMinor.keySignature.map(\.name), ["F♯"])
    }

    func testParallelKeyKeepsTonicFlipsMode() {
        let cMajor = Key.major(circlePosition: 0)
        let cMinor = cMajor.parallel
        XCTAssertEqual(cMinor.tonic.name, "C")
        XCTAssertEqual(cMinor.mode, .minor)
    }

    // MARK: - Enharmonic spelling distinction

    func testFSharpVersusGFlatMajorHaveDifferentSignatures() {
        // Same sound, different spelling → different signatures (+6 vs -6).
        XCTAssertEqual(Key.major(circlePosition: 6).sharpsOrFlats, 6)
        XCTAssertEqual(Key.major(circlePosition: -6).sharpsOrFlats, -6)
    }
}
