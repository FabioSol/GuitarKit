//
//  MPMPitchDetectorTests.swift
//  GuitarKitTests
//
//  Tests for the live detector's orchestration — gate → detect → smooth →
//  resolve → publish — driven through its hardware-free `process` entry point
//  with synthetic signals.
//
//  `@MainActor` on the class because `MPMPitchDetector` is main-actor isolated
//  (it publishes observable UI state); the tests must run there to touch it.
//

import XCTest
@testable import GuitarKit

@MainActor
final class MPMPitchDetectorTests: XCTestCase {

    private let sampleRate = 44_100.0

    func test_process_sustainedTone_publishesCorrectNote() {
        let detector = MPMPitchDetector()
        // A3 = 220 Hz.
        detector.process(samples: Signal.sine(frequency: 220, sampleRate: sampleRate),
                         sampleRate: sampleRate)

        let reading = detector.reading
        XCTAssertNotNil(reading)
        XCTAssertEqual(reading?.note, Note(pitchClass: .a, octave: 3))
        XCTAssertEqual(reading?.centOffset ?? .nan, 0, accuracy: 5)
        XCTAssertGreaterThan(reading?.clarity ?? 0, 0.9)
    }

    func test_process_silence_publishesNilReading() {
        let detector = MPMPitchDetector()
        detector.process(samples: [Float](repeating: 0, count: 4_096), sampleRate: sampleRate)
        XCTAssertNil(detector.reading)
    }

    func test_process_belowLevelGate_publishesNilReading() {
        let detector = MPMPitchDetector()
        // A real 220 Hz tone, but far too quiet to clear the −45 dBFS gate.
        let whisper = Signal.sine(frequency: 220, sampleRate: sampleRate, amplitude: 0.0001)
        detector.process(samples: whisper, sampleRate: sampleRate)
        XCTAssertNil(detector.reading)
    }

    func test_process_thenSilence_clearsReading() {
        let detector = MPMPitchDetector()
        // First a clear tone…
        detector.process(samples: Signal.sine(frequency: 330, sampleRate: sampleRate),
                         sampleRate: sampleRate)
        XCTAssertNotNil(detector.reading)
        // …then silence should drop the reading back to nil.
        detector.process(samples: [Float](repeating: 0, count: 4_096), sampleRate: sampleRate)
        XCTAssertNil(detector.reading)
    }

    func test_reset_clearsReading() {
        let detector = MPMPitchDetector()
        detector.process(samples: Signal.sine(frequency: 440, sampleRate: sampleRate),
                         sampleRate: sampleRate)
        XCTAssertNotNil(detector.reading)
        detector.reset()
        XCTAssertNil(detector.reading)
    }
}
