//
//  MetronomeViewModelTests.swift
//  GuitarKitTests
//
//  The metronome's CONFIG state machine — the part that runs without touching the
//  audio engine. Every behaviour here happens while stopped (`isPlaying == false`),
//  so no click ever sounds: BPM clamping, tap-tempo nudging, and the way changing
//  the time signature resizes the per-beat accent pattern (preserving the player's
//  choices and the downbeat accent).
//
//  `@MainActor` because the view model is main-actor isolated.
//

import XCTest
@testable import GuitarKit

@MainActor
final class MetronomeViewModelTests: XCTestCase {

    // MARK: - BPM clamping

    func test_bpm_defaultsTo120() {
        XCTAssertEqual(MetronomeViewModel().bpm, 120)
    }

    func test_bpm_clampsToRange() {
        let vm = MetronomeViewModel()
        vm.bpm = 10            // below the 30 floor
        XCTAssertEqual(vm.bpm, MetronomeViewModel.minBPM)
        vm.bpm = 5000          // above the 300 ceiling
        XCTAssertEqual(vm.bpm, MetronomeViewModel.maxBPM)
        vm.bpm = 144           // in range — untouched
        XCTAssertEqual(vm.bpm, 144)
    }

    func test_nudge_adjustsAndClamps() {
        let vm = MetronomeViewModel()
        vm.bpm = 120
        vm.nudge(by: 6)
        XCTAssertEqual(vm.bpm, 126)
        vm.nudge(by: -200)     // would undershoot → clamps to the floor
        XCTAssertEqual(vm.bpm, MetronomeViewModel.minBPM)
    }

    // MARK: - Time signature ⇄ beat-ring + accents

    func test_default_isFourFour_withDownbeatAccent() {
        let vm = MetronomeViewModel()
        XCTAssertEqual(vm.beatsPerBar, 4)
        XCTAssertEqual(vm.beatAccents, [.accent, .normal, .normal, .normal])
    }

    func test_shrinkingTimeSignature_keepsLeadingAccents() {
        let vm = MetronomeViewModel()
        // Mark beat 2 as muted, then shrink to 3/4 — the first three choices survive.
        vm.cycleAccent(at: 2)               // .normal → .muted
        vm.cycleAccent(at: 2)               // .muted → .accent  (now [acc, norm, acc, norm])
        vm.setTimeSignature(.threeFour)
        XCTAssertEqual(vm.beatsPerBar, 3)
        XCTAssertEqual(vm.beatAccents, [.accent, .normal, .accent])
    }

    func test_growingTimeSignature_padsWithNormalAndKeepsDownbeat() {
        let vm = MetronomeViewModel()
        vm.setTimeSignature(.sixEight)      // 4 → 6 beats
        XCTAssertEqual(vm.beatsPerBar, 6)
        XCTAssertEqual(vm.beatAccents.count, 6)
        XCTAssertEqual(vm.beatAccents.first, .accent, "the downbeat accent must survive a grow")
        XCTAssertEqual(Array(vm.beatAccents.suffix(2)), [.normal, .normal], "new beats pad as normal")
    }

    func test_setCustomBeats_resizesAccents() {
        let vm = MetronomeViewModel()
        vm.setCustomBeats(5)
        XCTAssertEqual(vm.beatsPerBar, 5)
        XCTAssertEqual(vm.beatAccents.count, 5)
    }

    // MARK: - Cycling a beat's accent

    func test_cycleAccent_advancesThroughTheThreeStates() {
        let vm = MetronomeViewModel()
        XCTAssertEqual(vm.beatAccents[1], .normal)
        vm.cycleAccent(at: 1)
        XCTAssertEqual(vm.beatAccents[1], .muted)
        vm.cycleAccent(at: 1)
        XCTAssertEqual(vm.beatAccents[1], .accent)
        vm.cycleAccent(at: 1)
        XCTAssertEqual(vm.beatAccents[1], .normal)   // wrapped
    }

    func test_cycleAccent_ignoresOutOfRangeIndex() {
        let vm = MetronomeViewModel()
        let before = vm.beatAccents
        vm.cycleAccent(at: 99)
        XCTAssertEqual(vm.beatAccents, before, "an out-of-range beat index is a no-op")
    }

    // MARK: - Transport flags while stopped

    func test_startsStoppedAtDownbeat() {
        let vm = MetronomeViewModel()
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(vm.currentBeat, 0)
    }
}
