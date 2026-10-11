//
//  RotaryNavGeometryTests.swift
//  GuitarKitTests
//
//  The rotary nav's shortest-spin math, in isolation. Extracting `RotaryNavGeometry`
//  out of the SwiftUI view is what makes this testable: we assert the angle
//  wrapping, slot layout, and "spin the shortest way to bring a tool to the apex"
//  logic with no view, no animation, no device.
//

import XCTest
@testable import GuitarKit

final class RotaryNavGeometryTests: XCTestCase {

    // 5 tools × 8 copies = 40 slots, 9° apart — the shipping configuration.
    private let geo = RotaryNavGeometry(toolCount: 5, copies: 8)

    // MARK: - Layout basics

    func test_slotCountAndSpacing() {
        XCTAssertEqual(geo.slotCount, 40)
        XCTAssertEqual(geo.anglePerItem, 9, accuracy: 1e-9)   // 360 / 40
    }

    func test_slotZero_sitsAtTheApex() {
        XCTAssertEqual(geo.slotAngle(0), -90, accuracy: 1e-9)
        XCTAssertEqual(geo.slotAngle(1), -81, accuracy: 1e-9) // one step round
    }

    // MARK: - normalizeToShortest wraps into (−180, 180]

    func test_normalize_wrapsIntoShortestEquivalent() {
        XCTAssertEqual(geo.normalizeToShortest(0), 0, accuracy: 1e-9)
        XCTAssertEqual(geo.normalizeToShortest(90), 90, accuracy: 1e-9)
        XCTAssertEqual(geo.normalizeToShortest(180), 180, accuracy: 1e-9)   // upper bound kept
        XCTAssertEqual(geo.normalizeToShortest(181), -179, accuracy: 1e-9)  // just over → negative
        XCTAssertEqual(geo.normalizeToShortest(270), -90, accuracy: 1e-9)
        XCTAssertEqual(geo.normalizeToShortest(360), 0, accuracy: 1e-9)
        XCTAssertEqual(geo.normalizeToShortest(-180), 180, accuracy: 1e-9)  // lower bound flips up
        XCTAssertEqual(geo.normalizeToShortest(540), 180, accuracy: 1e-9)
    }

    // MARK: - nearestRotation

    func test_nearestRotation_toolAlreadyAtApex_doesNotMove() {
        // Tool 0 occupies slot 0 (the apex) when rotation is 0 → no spin needed.
        XCTAssertEqual(geo.nearestRotation(forToolIndex: 0, from: 0), 0, accuracy: 1e-9)
    }

    func test_nearestRotation_picksTheAdjacentCopy_notAFarOne() {
        // Tool 1's nearest slot from rest is the slot just clockwise of the apex
        // (slot 1, at −81°), so the shortest spin is a small backward turn of one
        // slot width (−9°) — NOT a big spin to some distant copy.
        let r = geo.nearestRotation(forToolIndex: 1, from: 0)
        XCTAssertEqual(r, -9, accuracy: 1e-6)
    }

    func test_nearestRotation_isAlwaysAShortestSpin() {
        // Whatever the tool or starting rotation, the chosen spin is never more than
        // half a turn (the wrap guarantees the shortest equivalent).
        for tool in 0..<5 {
            for start in stride(from: -400.0, through: 400.0, by: 37.0) {
                let r = geo.nearestRotation(forToolIndex: tool, from: start)
                XCTAssertLessThanOrEqual(abs(r - start), 180 + 1e-6,
                    "tool \(tool) from \(start) spun \(r - start)°, more than half a turn")
            }
        }
    }

    func test_nearestRotation_actuallyLandsTheToolOnTheApex() {
        // After spinning to the result, SOME slot showing the tool must sit at the
        // apex: (slotAngle(k) + result) ≡ −90 (mod 360) for one of the tool's slots.
        for tool in 0..<5 {
            for start in stride(from: -200.0, through: 200.0, by: 23.0) {
                let result = geo.nearestRotation(forToolIndex: tool, from: start)
                var landed = false
                var k = tool
                while k < geo.slotCount {
                    let apexError = geo.normalizeToShortest(geo.slotAngle(k) + result + 90)
                    if abs(apexError) < 1e-6 { landed = true; break }
                    k += geo.toolCount
                }
                XCTAssertTrue(landed, "tool \(tool) from \(start): no slot landed on the apex")
            }
        }
    }
}
