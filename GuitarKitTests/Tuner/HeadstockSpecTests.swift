//
//  HeadstockSpecTests.swift
//  GuitarKitTests
//
//  Tests for the designer-facing headstock spec: that the JSON shape decodes,
//  that the shipped guitar spec is present + well-formed, and that the standard
//  guitar always resolves (bundled JSON, or procedural fallback).
//

import XCTest
@testable import GuitarKit

final class HeadstockSpecTests: XCTestCase {

    // MARK: - Codable shape

    func test_decodesFromJSON() throws {
        // The exact shape a designer authors (art asset + aspect + peg anchors).
        let json = """
        {
          "artAsset": "headstock-guitar",
          "aspectRatio": 0.66,
          "pegs": [
            { "x": 0.24, "y": 0.67 },
            { "x": 0.76, "y": 0.25 }
          ]
        }
        """.data(using: .utf8)!

        let spec = try JSONDecoder().decode(HeadstockSpec.self, from: json)
        XCTAssertEqual(spec.artAsset, "headstock-guitar")
        XCTAssertEqual(spec.aspectRatio, 0.66, accuracy: 0.0001)
        XCTAssertEqual(spec.pegs.count, 2)
        XCTAssertEqual(spec.pegs[0], PegPosition(x: 0.24, y: 0.67))
    }

    func test_nullArtAsset_decodesAsProcedural() throws {
        // `artAsset: null` means "use the built-in procedural shape".
        let json = """
        { "artAsset": null, "aspectRatio": 0.66, "pegs": [] }
        """.data(using: .utf8)!
        let spec = try JSONDecoder().decode(HeadstockSpec.self, from: json)
        XCTAssertNil(spec.artAsset)
    }

    // MARK: - Standard guitar always resolves

    func test_standardGuitar_hasSixPegs() {
        // Whether from the bundled JSON or the procedural fallback, the standard
        // guitar must always present six peg anchors.
        XCTAssertEqual(HeadstockSpec.standardGuitar.pegs.count, 6)
    }

    func test_standardGuitar_lowEIsBottomLeft_highEIsBottomRight() {
        let pegs = HeadstockSpec.standardGuitar.pegs
        // String 0 (low E) bottom-left; string 5 (high E) bottom-right.
        XCTAssertLessThan(pegs[0].x, 0.5)
        XCTAssertGreaterThan(pegs[0].y, 0.5)
        XCTAssertGreaterThan(pegs[5].x, 0.5)
        XCTAssertGreaterThan(pegs[5].y, 0.5)
    }

    // MARK: - Bundled JSON

    func test_bundledGuitarJSON_loads() {
        // Confirms guitar.json is actually bundled and decodes (exercises the
        // real designer pipeline, not just the fallback).
        let spec = HeadstockSpec.load("guitar")
        XCTAssertNotNil(spec, "guitar.json should be bundled as a resource")
        XCTAssertEqual(spec?.pegs.count, 6)
    }

    // MARK: - Nut + string routing (data-driven)

    func test_decodesNutAndStringRouting() throws {
        let json = """
        {
          "artAsset": "x", "aspectRatio": 0.5,
          "nut": { "x": 0.57, "y": 0.9, "width": 0.22 },
          "pegs": [
            { "x": 0.2, "y": 0.6, "crossesNut": false },
            { "x": 0.14, "y": 0.7, "stringX": 0.43, "stringY": 0.68 }
          ]
        }
        """.data(using: .utf8)!
        let spec = try JSONDecoder().decode(HeadstockSpec.self, from: json)
        XCTAssertEqual(spec.nut, NutSpec(x: 0.57, y: 0.9, width: 0.22))
        XCTAssertEqual(spec.pegs[0].crossesNut, false)
        XCTAssertEqual(spec.pegs[1].stringX, 0.43)
        XCTAssertEqual(spec.pegs[1].stringY, 0.68)
        // Unspecified routing fields default to nil (→ dot position / crosses nut).
        XCTAssertNil(spec.pegs[1].crossesNut)
        XCTAssertNil(spec.pegs[0].stringX)
    }

    func test_resolvedNut_defaultsWhenAbsent() throws {
        let json = #"{ "artAsset": null, "aspectRatio": 0.66, "pegs": [] }"#.data(using: .utf8)!
        let spec = try JSONDecoder().decode(HeadstockSpec.self, from: json)
        XCTAssertNil(spec.nut)
        XCTAssertEqual(spec.resolvedNut, NutSpec.default)
    }

    // MARK: - Every bundled instrument spec is well-formed

    func test_allInstrumentSpecs_loadWithExpectedPegCounts() {
        // file name → expected peg count (= string count).
        let expected: [(String, Int)] = [
            ("guitar", 6), ("guitar-7", 7), ("bass-4", 4), ("bass-5", 5),
            ("ukulele", 4), ("violin", 4), ("banjo-5", 5)
        ]
        for (name, count) in expected {
            let spec = HeadstockSpec.load(name)
            XCTAssertNotNil(spec, "\(name).json should be bundled")
            XCTAssertEqual(spec?.pegs.count, count, "\(name) peg count")
            XCTAssertNotNil(spec?.nut, "\(name) should author a nut")
        }
    }

    func test_banjoDrone_doesNotCrossNut() {
        // The 5th (drone) string must be excluded from the nut fan so it can't skew
        // the other four off-centre.
        let spec = HeadstockSpec.load("banjo-5")
        XCTAssertEqual(spec?.pegs.first?.crossesNut, false)
    }

    func test_violin_hidesStrings() {
        // The violin draws no string lines (its strings hide inside the pegbox).
        let spec = HeadstockSpec.load("violin")
        XCTAssertEqual(spec?.showStrings, false)
    }

    func test_showStrings_defaultsTrueWhenAbsent() throws {
        let json = #"{ "artAsset": null, "aspectRatio": 0.66, "pegs": [] }"#.data(using: .utf8)!
        let spec = try JSONDecoder().decode(HeadstockSpec.self, from: json)
        XCTAssertNil(spec.showStrings)   // absent → view treats as `true`
    }
}
