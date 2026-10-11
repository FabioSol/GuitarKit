//
//  RealisticGuitarFixturesTests.swift
//  GuitarKitTests
//
//  The pure detectors and the full `process` pipeline, faced with the MESSY
//  signals a real guitar produces — the cases behind the "flaky low string"
//  reports. Ideal-sine tests (MPMTests/YINTests) prove the math; these prove
//  robustness against what actually comes off a pickup:
//    • a WEAK fundamental (overtones louder than the root),
//    • HARMONIC-DOMINANT tones (a partial is the loudest thing present),
//    • INHARMONICITY (stiff strings push overtones sharp),
//    • DECAY (the pluck fades to a quiet, less-periodic tail), and
//    • mains HUM / sub-bass RUMBLE sitting under a low note.
//
//  Tolerances are in CENTS (the musically meaningful unit). We allow a touch more
//  slack than the pure-sine tests (~8–12¢) because these signals are genuinely
//  ambiguous — but still well inside "the note is right", which is the contract a
//  tuner must keep.
//

import XCTest
@testable import GuitarKit

final class RealisticGuitarFixturesTests: XCTestCase {

    private let sampleRate = 44_100.0

    /// |detected − expected| in cents, or `.infinity` if nothing was detected.
    private func cents(_ estimate: PitchEstimate?, from expected: Double) -> Double {
        guard let estimate else { return .infinity }
        return abs(PitchCalculator.cents(from: Double(estimate.frequency), to: expected))
    }

    /// Assert EVERY algorithm (MPM, YIN, ensemble) recovers `expected` within
    /// `tolerance` cents from `signal`. One helper keeps the matrix of fixtures ×
    /// algorithms readable.
    private func assertAllAlgorithmsRecover(
        _ signal: [Float],
        near expected: Double,
        withinCents tolerance: Double,
        _ label: String,
        algorithms: [PitchAlgorithm] = PitchAlgorithm.allCases,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for algorithm in algorithms {
            let estimate = algorithm.detect(samples: signal, sampleRate: sampleRate)
            let off = cents(estimate, from: expected)
            XCTAssertLessThanOrEqual(
                off, tolerance,
                "\(algorithm.label) on \(label): \(estimate.map { "\($0.frequency) Hz" } ?? "nil") is \(off)¢ from \(expected) Hz",
                file: file, line: line
            )
        }
    }

    // MARK: - Weak fundamental (the octave-error trap)

    func test_weakFundamental_lowE_reportsFundamental() {
        // Low E (82.41 Hz) with the root much quieter than the 2nd/3rd partials —
        // the body/pickup emphasise the mids. A naive detector reports an octave up.
        let s = Signal.harmonicTone(
            fundamental: 82.41,
            harmonicAmplitudes: [0.18, 1.0, 0.7, 0.4, 0.25]
        )
        assertAllAlgorithmsRecover(s, near: 82.41, withinCents: 8, "weak-fundamental low E")
    }

    func test_harmonicDominant_A2_reportsFundamental() {
        // A2 (110 Hz) whose 2nd harmonic is the single loudest partial.
        let s = Signal.harmonicTone(
            fundamental: 110,
            harmonicAmplitudes: [0.3, 1.0, 0.8, 0.4]
        )
        assertAllAlgorithmsRecover(s, near: 110, withinCents: 8, "harmonic-dominant A2")
    }

    // MARK: - Inharmonicity (stiff strings stretch the overtones sharp)

    func test_inharmonicLowE_staysWithinTuningTolerance() {
        // Stiff-string overtones drift sharp; the detector may get tugged a few
        // cents up, but must stay well inside "still E2" (not an octave or a
        // semitone off).
        let s = Signal.inharmonicTone(
            fundamental: 82.41,
            harmonicAmplitudes: [0.4, 1.0, 0.7, 0.4],
            inharmonicity: 0.0005
        )
        assertAllAlgorithmsRecover(s, near: 82.41, withinCents: 12, "inharmonic low E")
    }

    // MARK: - Decay (the fading tail of a pluck)

    func test_decayingLowE_isStillDetected() {
        // A fast-decaying low E (time-constant 120 ms): by the buffer's end the
        // amplitude has dropped sharply, but the period is unchanged, so the pitch
        // must still resolve.
        let s = Signal.decaying(
            Signal.harmonicTone(fundamental: 82.41, harmonicAmplitudes: [0.4, 1.0, 0.7, 0.4]),
            decayTime: 0.12
        )
        assertAllAlgorithmsRecover(s, near: 82.41, withinCents: 8, "decaying low E")
    }

    // MARK: - The "everything at once" plucked note

    func test_pluckedGuitarNote_lowE_resolves() {
        // Weak root + inharmonicity + decay, bundled — the everyday hard case.
        let s = Signal.pluckedGuitarNote(fundamental: 82.41)
        assertAllAlgorithmsRecover(s, near: 82.41, withinCents: 10, "plucked low E")
    }

    func test_pluckedGuitarNote_A2_resolves() {
        let s = Signal.pluckedGuitarNote(fundamental: 110)
        assertAllAlgorithmsRecover(s, near: 110, withinCents: 10, "plucked A2")
    }

    // MARK: - Tone buried in mains hum (moderate)

    func test_lowE_underMainsHum_resolves() {
        // A clearly-audible low E with 60 Hz hum under it (hum ~half the tone).
        // The fundamental still wins; the detector reports E2.
        let s = Signal.mix(
            Signal.harmonicTone(fundamental: 82.41, harmonicAmplitudes: [0.4, 1.0, 0.6]),
            Signal.hum(frequency: 60, amplitude: 0.5)
        )
        // HPS is excluded here: a strong sub-fundamental 60 Hz hum drags it to a
        // subharmonic (the band-pass preprocessor removes that hum before HPS sees
        // it in the real pipeline). MPM/YIN/ensemble handle the raw signal directly.
        assertAllAlgorithmsRecover(s, near: 82.41, withinCents: 8, "low E under mains hum",
                                   algorithms: [.mpm, .yin, .ensemble])
    }

    // MARK: - The full pipeline through PitchTracker.process

    @MainActor
    func test_process_pluckedLowE_readsE2() {
        // The real pipeline (preprocess → in-band gate → ensemble → continuity →
        // smooth → resolve) must turn a realistic plucked low E into the E2 note
        // the UI shows. Two frames: onset confirmation reads on the second.
        var tracker = PitchTracker()
        let s = Signal.pluckedGuitarNote(fundamental: 82.41)
        _ = tracker.process(samples: s, sampleRate: sampleRate)
        let reading = tracker.process(samples: s, sampleRate: sampleRate)
        XCTAssertEqual(reading?.note, Note(pitchClass: .e, octave: 2))
        XCTAssertLessThanOrEqual(abs(reading?.centOffset ?? .infinity), 12)
    }

    @MainActor
    func test_process_weakFundamentalA2_readsA2() {
        var tracker = PitchTracker()
        let s = Signal.harmonicTone(fundamental: 110, harmonicAmplitudes: [0.2, 1.0, 0.7, 0.4])
        _ = tracker.process(samples: s, sampleRate: sampleRate)
        XCTAssertEqual(tracker.process(samples: s, sampleRate: sampleRate)?.note,
                       Note(pitchClass: .a, octave: 2))
    }
}
