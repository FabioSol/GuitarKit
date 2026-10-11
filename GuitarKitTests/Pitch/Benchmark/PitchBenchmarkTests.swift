//
//  PitchBenchmarkTests.swift
//  GuitarKitTests
//
//  Runs the pitch benchmark and writes `PitchBench/RESULTS.md`. This is a
//  MEASUREMENT, not a pass/fail gate: it only fails if a clip can't be loaded.
//  Compare RESULTS.md before and after a change (it's plain text, so
//  `git diff PitchBench/RESULTS.md` shows exactly what moved). The other tests
//  here check the harness itself and always run.
//

import XCTest
@testable import GuitarKit

@MainActor
final class PitchBenchmarkTests: XCTestCase {

    func test_benchmark_writesResults() throws {
        // The full run takes minutes in an unoptimized Debug build, so ⌘U
        // skips it. Run it with PITCH_BENCH=1 — or, much faster, with
        // `PitchBench/run.sh` (see PitchBench/README.md).
        guard ProcessInfo.processInfo.environment["PITCH_BENCH"] == "1" else {
            throw XCTSkip("Set PITCH_BENCH=1 (or use PitchBench/run.sh) to run the full benchmark")
        }
        print(try PitchBenchmark.writeResults())
    }

    // MARK: - The harness's own scoring

    func test_cleanSustainedTone_scoresAsDetected() {
        // A loud, steady A3 in silence must score as detected with near-full
        // coverage — guards the scoring math itself.
        let rate = 44_100.0
        let samples = [Float](repeating: 0, count: 8_192)
            + Signal.sine(frequency: 220, sampleRate: rate, count: 4_096 * 10, amplitude: 0.3)
        let clip = BenchClip(name: "sine", samples: samples, sampleRate: rate,
                             windowFrames: 4_096, expectedHz: 220, pluck: "hard",
                             background: "quiet", band: .full, referencePitch: .standard)
        let result = PitchBenchmark.run(clip)
        XCTAssertTrue(result.detected)
        XCTAssertEqual(result.wrongReadings, 0)
        // The first window is held for confirmation, so at most one is missed.
        XCTAssertGreaterThanOrEqual(result.coverage ?? 0, 0.9)
        XCTAssertEqual(result.medianCents ?? .nan, 0, accuracy: 3)
    }

    func test_everyInterference_rendersAtRequestedLevel_deterministically() {
        for kind in Interference.allCases where kind != .quietRoom {
            let a = kind.render(count: 44_100, sampleRate: 44_100, levelDBFS: -40, seed: 5)
            let b = kind.render(count: 44_100, sampleRate: 44_100, levelDBFS: -40, seed: 5)
            XCTAssertEqual(a, b, "\(kind.rawValue) must be identical for the same seed")
            XCTAssertEqual(AudioLevel.rms(of: a), 0.01, accuracy: 0.0005,
                           "\(kind.rawValue) must render at −40 dBFS RMS")
        }
    }

    func test_gaussianNoise_isZeroMeanAtRequestedRMS() {
        let noise = PitchBenchmark.gaussianNoise(count: 44_100, rms: 0.01, seed: 3)
        let mean = noise.reduce(0, +) / Float(noise.count)
        XCTAssertEqual(mean, 0, accuracy: 0.001)
        XCTAssertEqual(AudioLevel.rms(of: noise), 0.01, accuracy: 0.001)
    }
}
