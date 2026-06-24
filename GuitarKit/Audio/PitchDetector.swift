//
//  PitchDetector.swift
//  GuitarKit
//
//  The live, observable pitch detector that the Tuner UI binds to. It is the
//  bridge between three pure pieces and the noisy real world:
//
//      audio buffers ──▶ [RMS gate] ──▶ MPM.detectPitch ──▶ PitchSmoother
//                                                                 │
//                        PitchCalculator.nearestNote ◀────────────┘
//                                   │
//                                   ▼
//                              published `reading`  ──▶ SwiftUI
//
//  WHY A PROTOCOL IN FRONT OF IT (`PitchDetecting`)?
//  Same reasoning as `AudioInputProviding`: the UI and tests should depend on a
//  small interface, not this concrete class. It also documents the seam the next
//  slice (#05, targeted tuning) plugs into — that slice consumes `reading` and
//  compares it against a chosen string's target.
//
//  WHY IS `process` PUBLIC AND BUFFER-FREE?
//  Detection is fully exercisable from a *synthetic* `[Float]` feed — no mic. The
//  live path (`attach(to:)`) just converts hardware buffers into that same call,
//  so tests drive `process(samples:sampleRate:)` directly with a known sine wave.
//

import AVFoundation
import Observation

// MARK: - The reading the UI consumes

/// One fully-resolved pitch reading: the smoothed frequency, the note we believe
/// is sounding, how many cents off it is, and a 0…1 confidence. `nil` reading
/// (on the detector) means "nothing detected right now" (silence/noise).
///
/// A plain value `struct` — immutable result, `Equatable` so SwiftUI can tell
/// when it actually changed.
struct PitchReading: Equatable {
    /// Smoothed fundamental frequency, in Hz.
    let frequency: Double
    /// The nearest equal-tempered note (the chromatic readout).
    let note: Note
    /// Signed cents from that note: positive = sharp, negative = flat.
    let centOffset: Double
    /// Detector confidence, 0…1 (the MPM clarity of this estimate).
    let clarity: Float
}

// MARK: - The seam

/// What any pitch detector exposes. Class-bound + `@MainActor` because `reading`
/// is observable UI state read on the main thread.
@MainActor
protocol PitchDetecting: AnyObject {
    /// The latest reading, or `nil` when nothing confident is detected.
    var reading: PitchReading? { get }

    /// Process one window of mono samples (the testable, hardware-free entry).
    func process(samples: [Float], sampleRate: Double)

    /// Drop transient state (smoothing history) — call when audio stops.
    func reset()
}

// MARK: - The MPM-backed implementation

/// Concrete detector built on `MPM` + `PitchSmoother` + `PitchCalculator`.
///
/// `@Observable` so SwiftUI re-renders when `reading` changes; `@MainActor`
/// because that published state lives on the main thread.
@MainActor
@Observable
final class MPMPitchDetector: PitchDetecting {

    // MARK: Published output

    /// The current reading, written by the engine and read-only to the UI.
    private(set) var reading: PitchReading?

    // MARK: Collaborators / config (not observed — plumbing, not UI state)

    /// Resolves a frequency to its nearest note. Carries the user's reference
    /// pitch (e.g. A=440), so recalibrating later just swaps this in.
    @ObservationIgnored private let calculator: PitchCalculator

    /// The de-jitter/smoothing stage. `var` because `push`/`reset` mutate it.
    @ObservationIgnored private var smoother = PitchSmoother()

    /// Which detection algorithm to run (MPM / YIN / Ensemble). `var` so it can
    /// be swapped live in the Tuner Lab. Defaults to the ensemble for robustness.
    @ObservationIgnored private var algorithm: PitchAlgorithm

    /// MPM's confidence gate: estimates below this clarity are discarded. `var`
    /// so it can be tuned live (the Tuner Lab). Default loosened to admit plucked
    /// guitar — a decaying, slightly inharmonic string scores lower clarity than
    /// a sustained voice, so a high gate silently dropped most guitar notes.
    @ObservationIgnored private var clarityThreshold: Float

    /// The level gate, as a raw RMS amplitude. Below this we treat the buffer as
    /// silence/background and publish no reading — satisfying the PRD's "don't
    /// twitch on noise". We store it as linear RMS (converted from a dBFS
    /// threshold once) so the per-buffer check is a cheap comparison. `var` so it
    /// can be tuned live.
    @ObservationIgnored private var levelGateRMS: Float

    /// - Parameters:
    ///   - calculator: tuning context for note resolution (defaults to A=440,
    ///     equal temperament).
    ///   - clarityThreshold: minimum MPM clarity to accept (0…1). Lower = catches
    ///     more (decaying/quiet guitar) but risks twitching on noise.
    ///   - levelGateDB: quietest signal we'll analyze, in dBFS. Lower admits the
    ///     decaying tail of a plucked note instead of dropping it after the attack.
    init(
        calculator: PitchCalculator? = nil,
        algorithm: PitchAlgorithm = .ensemble,
        clarityThreshold: Float = 0.6,
        levelGateDB: Float = -52
    ) {
        // Default to A=440 / equal temperament. We build it HERE rather than as a
        // default argument: under this project's main-actor-by-default isolation,
        // default-argument expressions run in a non-isolated context where the
        // (isolated) `PitchCalculator` initializer can't be called.
        self.calculator = calculator ?? PitchCalculator()
        self.algorithm = algorithm
        self.clarityThreshold = clarityThreshold
        // dBFS → linear RMS: amplitude = 10^(dB / 20).
        self.levelGateRMS = pow(10, levelGateDB / 20)
    }

    // MARK: Core (testable) processing

    /// Run the full pipeline on one window of samples and publish the result.
    func process(samples: [Float], sampleRate: Double) {
        // 1) LEVEL GATE. Cheap RMS first — if it's basically silence, bail out
        // and forget history so the next note starts fresh. Reusing the pure
        // `AudioLevel.rms` keeps one definition of "loudness".
        let rms = AudioLevel.rms(of: samples)
        guard rms >= levelGateRMS else {
            reading = nil
            smoother.reset()
            return
        }

        // 2) DETECT with the chosen algorithm (MPM / YIN / Ensemble). It returns
        // a RAW estimate; we apply the clarity gate here so the same gate works
        // for every algorithm.
        guard let estimate = algorithm.detect(samples: samples, sampleRate: sampleRate) else {
            reading = nil
            return
        }
        // CLARITY GATE: reject noisy-but-loud signals (low periodicity).
        guard estimate.clarity >= clarityThreshold else {
            reading = nil
            return
        }

        // 3) SMOOTH the raw frequency (kills octave-jump outliers + wobble).
        let smoothed = smoother.push(estimate.frequency)

        // 4) RESOLVE to a note + cents and publish.
        guard let resolved = calculator.nearestNote(toFrequency: Double(smoothed)) else {
            reading = nil
            return
        }
        reading = PitchReading(
            frequency: Double(smoothed),
            note: resolved.note,
            centOffset: resolved.centOffset,
            clarity: estimate.clarity
        )
    }

    func reset() {
        smoother.reset()
        reading = nil
    }

    /// Replace the smoother with one tuned to a new EMA factor (0…1). Used by the
    /// debug "Tuner Lab" panel (slice #07) to A/B smoothing live; the new factor
    /// takes effect on the next reading. We rebuild rather than mutate because the
    /// factor is set once at `PitchSmoother` init; history is dropped (a clean
    /// restart), which is exactly what we want when changing how smoothing behaves.
    func setSmoothing(emaFactor: Float) {
        smoother = PitchSmoother(emaFactor: emaFactor)
    }

    /// Set the MPM clarity gate live (Tuner Lab). Lower catches more guitar;
    /// higher rejects more noise.
    func setClarityThreshold(_ value: Float) {
        clarityThreshold = min(max(value, 0), 1)
    }

    /// Set the level (RMS) gate live, from a dBFS value. Lower admits quieter /
    /// decaying notes.
    func setLevelGate(dB: Float) {
        levelGateRMS = pow(10, dB / 20)
    }

    /// Swap the detection algorithm live (Tuner Lab): MPM / YIN / Ensemble.
    func setAlgorithm(_ algorithm: PitchAlgorithm) {
        self.algorithm = algorithm
    }

    // MARK: Live wiring

    /// Subscribe this detector to a live audio source. Each hardware buffer is
    /// converted to samples and fed through `process`.
    ///
    /// THREADING: the source calls our closure on a real-time *audio thread*, so
    /// we do only the cheap buffer→`[Float]` copy there, then hop to the main
    /// actor (where this detector lives) to run detection and publish. Detection
    /// for one ~4096-sample buffer is light and fires only ~10×/second, so the
    /// main thread handles it comfortably without stutter.
    func attach(to source: AudioInputProviding) {
        source.onBuffer { [weak self] buffer in
            // On the audio thread: read the format and copy out the samples.
            let sampleRate = buffer.format.sampleRate
            let samples = AudioInputEngine.samples(from: buffer)

            // Hop to the main actor to analyze + publish.
            Task { @MainActor in
                self?.process(samples: samples, sampleRate: sampleRate)
            }
        }
    }
}
