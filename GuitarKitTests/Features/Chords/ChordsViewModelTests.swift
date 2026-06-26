//
//  ChordsViewModelTests.swift
//  GuitarKitTests
//
//  The Chords tool's voicing-cycle state: stepping through alternate shapes,
//  wrapping at the end, resetting to the first, and never indexing off the end when
//  the chord changes to one with fewer alternates. Driven on the default standard-
//  guitar board (no store), where a familiar chord like C major has several shapes.
//

import XCTest
@testable import GuitarKit

@MainActor
final class ChordsViewModelTests: XCTestCase {

    func test_cmajor_hasMultipleVoicings() {
        let vm = ChordsViewModel()
        vm.root = .c
        vm.quality = .major
        XCTAssertGreaterThan(vm.voicingCount, 1,
            "C major on standard guitar should offer the open shape plus moveable barres")
    }

    func test_cycleVoicing_advancesThenWraps() {
        let vm = ChordsViewModel()
        vm.root = .c
        vm.quality = .major
        let count = vm.voicingCount

        XCTAssertEqual(vm.voicingIndex, 0)
        for expected in 1..<count {
            vm.cycleVoicing()
            XCTAssertEqual(vm.voicingIndex, expected)
        }
        // One more cycle wraps back to the first.
        vm.cycleVoicing()
        XCTAssertEqual(vm.voicingIndex, 0)
    }

    func test_resetVoicing_returnsToFirst() {
        let vm = ChordsViewModel()
        vm.root = .c
        vm.quality = .major
        vm.cycleVoicing()
        XCTAssertNotEqual(vm.voicingIndex, 0)
        vm.resetVoicing()
        XCTAssertEqual(vm.voicingIndex, 0)
    }

    func test_currentVoicing_clampsStaleIndex() {
        let vm = ChordsViewModel()
        vm.root = .c
        vm.quality = .major
        // Push the index past the end (as a chord change to fewer shapes would
        // leave it). `currentVoicing` must clamp instead of trapping.
        vm.voicingIndex = 999
        let last = vm.alternateVoicings.last
        XCTAssertEqual(vm.currentVoicing, last,
            "a stale out-of-range index should clamp to the last available voicing")
    }

    func test_firstVoicing_isTheLowestShape() {
        // The list is ordered low → high, so index 0 sits at or below every other.
        let vm = ChordsViewModel()
        vm.root = .c
        vm.quality = .major
        let list = vm.alternateVoicings
        let firstHeight = list.first?.lowestFrettedFret ?? 0
        for v in list {
            XCTAssertLessThanOrEqual(firstHeight, v.lowestFrettedFret ?? 0)
        }
    }
}
