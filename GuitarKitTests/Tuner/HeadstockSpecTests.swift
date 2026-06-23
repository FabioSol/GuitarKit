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
}
