//
//  PitchTracker.swift
//  GuitarKit
//
//  The WHOLE pitch pipeline as one pure value: mono samples in, an optional
//  `PitchReading` out. No audio hardware, no UI, no threads — which is what
//  lets the same code run live (behind `PitchDetector`) and in the benchmark
//  that replays recorded guitar clips (`GuitarKitTests/Pitch/Benchmark`).
//
//      samples ──▶ band-pass (PitchPreprocessor)
//                        │
//                        ▼
//                 [in-band RMS gate] ──▶ detect ──▶ [clarity gate]
//                        │                                │
//                        ▼                                ▼
//                 PitchContinuity (dropout + onset confirmation)
//                        │
//                        ▼
//                  PitchSmoother ──▶ PitchCalculator.nearestNote ──▶ reading
//
//  Note the ORDER: preprocessing runs FIRST so the level gate measures the
//  FILTERED (in-band) signal — "is there energy where a note could be?" —
//  instead of the raw buffer, where out-of-band rumble could hold the gate
//  open through a silence. The per-buffer gates grade each frame; then
//  `PitchContinuity` judges the STREAM, so an isolated noise frame never
//  becomes a reading.
//
//  THE INTERFACE IS SMALL ON PURPOSE: `process`, `reset`, and one `config`
//  value. Every knob — the tuning-derived band, the reference pitch, the
//  algorithm, the gates, smoothing — lives in `PitchTrackerConfig`, so callers
//  (the coordinator, the Tuner Lab, the benchmark) all change behaviour the
//  same way: edit the config. The stages inside are implementation details.
//

import Foundation

// MARK: - The reading

/// One fully-resolved pitch reading: the smoothed frequency, the note we believe
/// is sounding, how many cents off it is, and a 0…1 confidence.
///
/// A plain value `struct` — immutable result, `Equatable` so SwiftUI can tell
/// when it actually changed.
nonisolated struct PitchReading: Equatable {
    /// Smoothed fundamental frequency, in Hz.
    let frequency: Double
    /// The nearest equal-tempered note (the chromatic readout).
    let note: Note
    /// Signed cents from that note: positive = sharp, negative = flat.
    let centOffset: Double
    /// Detector confidence, 0…1 (the clarity of this estimate).
    let clarity: Float
}

// MARK: - Configuration

/// Everything that tunes the tracker's behaviour, as one value.
///
/// The defaults were field-calibrated on a real (quiet, unamplified) guitar
/// with the Tuner Lab. The benchmark in `PitchBench/` is how we check any
/// change to them.
nonisolated struct PitchTrackerConfig: Equatable {
    /// Where to look: the algorithms' search range + the band-pass corners.
    /// `.full` = no prior (chromatic, editor capture); the coordinator narrows
    /// it to the selected tuning in targeted mode.
    var band: DetectionBand = .full

    /// The A4 calibration used to NAME the note (`PitchReading.note` /
    /// `centOffset`). Must match the user's Settings, or the chromatic readout
    /// disagrees with the targeted tuner.
    var referencePitch: ReferencePitch = .standard

    /// Which detection algorithm runs (MPM / YIN / HPS / ensemble).
    var algorithm: PitchAlgorithm = .ensemble

    /// Onset clarity gate (0…1): estimates below this can't START a note.
    /// Plucked strings decay and are slightly inharmonic, so they score lower
    /// clarity than a sustained voice — too high a gate drops most guitar notes.
    var clarityThreshold: Float = 0.45

    /// Onset level gate in dBFS, measured on the band-passed signal. Quieter
    /// frames can't START a note.
    var levelGateDB: Float = -68

    /// The smoother's EMA factor (0…1): near 0 = smooth but laggy, near 1 =
    /// snappy but jittery.
    var smoothing: Float = 0.4

    /// Band-pass preprocessing on/off (the corners always come from `band`).
    var preprocessingEnabled = true

    // MARK: Finer knobs
    //
    // Reasoned defaults, exposed so the benchmark's parameter search
    // (`PitchBench/tune.py`) can test that reasoning. The Tuner Lab leaves
    // them alone.

    /// How many recent estimates the smoother's median looks at (odd).
    var smootherWindow = 5

    /// Sustain clarity gate as a fraction of the onset gate: once a note is
    /// confirmed, frames near its pitch stay alive down to this clarity.
    var sustainClarityFactor: Float = 0.65

    /// How far (dB) below the onset level gate a confirmed note's tail may
    /// fall and still be tracked.
    var sustainLevelReliefDB: Float = 6

    /// Consecutive rejected frames that end a note (and drop its history).
    var dropoutFrames = 2

    /// How close (cents) two frames must be to count as the same pitch — for
    /// confirming an onset and for accepting a sustain frame.
    var continuityAgreementCents: Float = 100

    // MARK: Harmonic check (targeted mode)
    //
    // A plucked string is ONE harmonic source: nearly all its energy sits on
    // f0, 2·f0, 3·f0… A voice glides (its upper harmonics smear), a chord has
    // other notes' energy, clicks and noise spread everywhere. So after the
    // detector names a pitch, we can ask how much of the sound sits on THAT
    // pitch's harmonic series (`HPS.harmonicity`) and refuse frames where the
    // answer is "not much". Off by default (0); meant for targeted mode, where
    // the target is always a string.

    /// Minimum harmonicity (0…1) for a frame to START a note. 0 = check off.
    var harmonicGate: Float = 0

    /// The gate targeted mode uses (chromatic mode leaves it off — it must
    /// hear any sound). Chosen from a sweep on real recordings with voices in
    /// the room: it cut wrong readings by about two thirds while keeping every
    /// note and pure tones intact; 0.70 and up started losing whole notes. See
    /// PitchBench/README.md, "The harmonic check".
    static let targetedModeHarmonicGate: Float = 0.65

    /// Sustain harmonicity as a fraction of `harmonicGate` — a confirmed
    /// note's decaying tail may score lower and still be tracked.
    var harmonicSustainFactor: Float = 0.6

    /// How many partials count as the harmonic series.
    var harmonicCount = 8

    // MARK: Engine

    /// Which pipeline turns detections into readings:
    ///   • `.gated` — per-frame gates + `PitchContinuity` (works anywhere);
    ///   • `.probabilistic` — `StringStateTracker`, a belief over which string
    ///     is ringing that builds up across frames. Needs `targetsHz` (targeted
    ///     mode); without targets it falls back to `.gated`.
    var engine: PitchEngine = .gated

    /// The strings' target frequencies (Hz, capo-shifted) in targeted mode;
    /// empty in chromatic mode / editor capture.
    var targetsHz: [Double] = []

    /// The probabilistic engine's knobs.
    var stringModel = StringStateTracker.Parameters()
}

nonisolated enum PitchEngine: String, CaseIterable, Sendable {
    case gated, probabilistic
}

// MARK: - The tracker

/// The pitch pipeline. A `struct` with `mutating` methods: it carries
/// per-stream state (filter memory, smoothing history, note continuity) but has
/// no identity — whoever owns it feeds it frames in order.
nonisolated struct PitchTracker {

    /// The active configuration. Assigning a new value applies only what
    /// changed — e.g. a new band retunes the filter and drops history (readings
    /// across a band change aren't comparable), while an unchanged band is a
    /// no-op, so callers can re-apply the config freely.
    var config: PitchTrackerConfig {
        didSet { apply(from: oldValue) }
    }

    // MARK: Stages (internal seams — tested through `process`)

    private var preprocessor: PitchPreprocessor
    private var continuity: PitchContinuity
    private var smoother: PitchSmoother
    private var calculator: PitchCalculator
    private var stringTracker: StringStateTracker
    /// The string the probabilistic engine showed last frame (to restart
    /// smoothing when it changes).
    private var shownString: Int?

    init(config: PitchTrackerConfig = PitchTrackerConfig()) {
        self.config = config
        // `didSet` doesn't run during init, so build each stage from the
        // config directly — the filter and the search range can never start
        // out disagreeing.
        preprocessor = PitchPreprocessor(highPassHz: config.band.highPassHz,
                                         lowPassHz: config.band.lowPassHz,
                                         enabled: config.preprocessingEnabled)
        smoother = Self.makeSmoother(config)
        continuity = Self.makeContinuity(config)
        calculator = PitchCalculator(referenceA: config.referencePitch)
        stringTracker = StringStateTracker(targets: config.targetsHz, parameters: config.stringModel)
    }

    // MARK: Processing

    /// Run one window of mono samples through the pipeline. Returns the reading
    /// to show, or `nil` for "nothing confident right now" (silence, noise, or a
    /// new note still waiting for its confirming frame).
    mutating func process(samples: [Float], sampleRate: Double) -> PitchReading? {
        // 1) PREPROCESS: band-pass so the fundamental dominates — and so the
        // level gate below measures only IN-BAND energy.
        let filtered = preprocessor.process(samples, sampleRate: sampleRate)

        if config.engine == .probabilistic, !config.targetsHz.isEmpty {
            return processProbabilistic(filtered, sampleRate: sampleRate)
        }

        // 2) GRADE THE FRAME. A frame that clears BOTH onset gates (level +
        // clarity) is `.strong`; one that clears only the relaxed SUSTAIN
        // gates is `.weak` (it can extend a tracked note's tail, never start
        // one). The sustain gates are derived from the onset gates, so one Lab
        // slider moves the whole hysteresis window together.
        let rms = AudioLevel.rms(of: filtered)
        let passesOnsetLevel = rms >= pow(10, config.levelGateDB / 20)          // dBFS → linear
        let passesSustainLevel = rms >= pow(10, (config.levelGateDB - config.sustainLevelReliefDB) / 20)

        var estimate: PitchEstimate?
        var frame: PitchContinuity.Frame?
        // Detection is worth running only if the frame could grade at all: at
        // onset level always; at sustain level only while a note is tracked.
        if passesOnsetLevel || (passesSustainLevel && continuity.isTrackingNote) {
            estimate = config.algorithm.detect(
                samples: filtered, sampleRate: sampleRate,
                minFrequency: Float(config.band.minFrequencyHz),
                maxFrequency: Float(config.band.maxFrequencyHz))
            if let e = estimate {
                // The harmonic check (1 when it's off, so it never blocks).
                let harmonicity = config.harmonicGate > 0
                    ? HPS.harmonicity(of: e.frequency, in: filtered, sampleRate: sampleRate,
                                      harmonics: config.harmonicCount,
                                      minFrequency: Float(config.band.minFrequencyHz)) ?? 0
                    : 1
                if passesOnsetLevel && e.clarity >= config.clarityThreshold
                    && harmonicity >= config.harmonicGate {
                    frame = .strong(e.frequency)
                } else if e.clarity >= config.clarityThreshold * config.sustainClarityFactor
                    && harmonicity >= config.harmonicGate * config.harmonicSustainFactor {
                    frame = .weak(e.frequency)
                }
            }
        }

        // 3) CONTINUITY: judge the graded stream.
        switch continuity.ingest(frame) {
        case .silence, .hold:
            return nil

        case .dropout:
            // The note ended: drop history so the next note starts clean.
            smoother.reset()
            preprocessor.reset()
            return nil

        case .track(let frequencies):
            // 4) SMOOTH. On onset confirmation there are two frequencies (the
            // held candidate + the confirming frame), so the smoother starts
            // from both real observations.
            var smoothed: Float = 0
            for frequency in frequencies {
                smoothed = smoother.push(frequency)
            }

            // 5) RESOLVE to a note + cents. `estimate` is always present on a
            // `.track` verdict (only graded frames produce one).
            guard let estimate,
                  let resolved = calculator.nearestNote(toFrequency: Double(smoothed)) else {
                return nil
            }
            return PitchReading(frequency: Double(smoothed),
                                note: resolved.note,
                                centOffset: resolved.centOffset,
                                clarity: estimate.clarity)
        }
    }

    /// The probabilistic path: describe the frame, let `StringStateTracker`
    /// update its belief, and read out the string it shows (if any).
    private mutating func processProbabilistic(_ filtered: [Float], sampleRate: Double) -> PitchReading? {
        let rms = AudioLevel.rms(of: filtered)
        let levelDB = rms > 0 ? 20 * log10(rms) : -160
        // One FFT per frame, shared by every question the model asks of it.
        let spectrum = HPS.spectrum(of: filtered, sampleRate: sampleRate)

        var candidate: StringStateTracker.Observation.Candidate?
        if levelDB > -110, let e = config.algorithm.detect(
            samples: filtered, sampleRate: sampleRate,
            minFrequency: Float(config.band.minFrequencyHz),
            maxFrequency: Float(config.band.maxFrequencyHz)) {
            let harmonicity = spectrum?.harmonicity(
                of: e.frequency, harmonics: config.harmonicCount,
                minFrequency: Float(config.band.minFrequencyHz)) ?? 0
            candidate = .init(frequency: e.frequency, clarity: e.clarity, harmonicity: harmonicity)
        }

        let decision = stringTracker.step(.init(
            levelDB: levelDB, candidate: candidate,
            salience: { spectrum?.salience(of: $0) },
            refine: { spectrum?.refinedPitch(near: $0) }))

        guard case let .ringing(index, frequency, probability) = decision else {
            if shownString != nil { smoother.reset() }
            shownString = nil
            return nil
        }
        // A different string: don't let the smoother glide from the old one.
        if index != shownString { smoother.reset() }
        shownString = index
        let smoothed = smoother.push(frequency)
        guard let resolved = calculator.nearestNote(toFrequency: Double(smoothed)) else { return nil }
        return PitchReading(frequency: Double(smoothed), note: resolved.note,
                            centOffset: resolved.centOffset, clarity: probability)
    }

    /// Forget all per-stream state — call when audio stops, so the next note
    /// starts from scratch.
    mutating func reset() {
        smoother.reset()
        preprocessor.reset()
        continuity.reset()
        stringTracker.reset()
        shownString = nil
    }

    // MARK: Applying config changes

    private mutating func apply(from old: PitchTrackerConfig) {
        if config.targetsHz != old.targetsHz || config.stringModel != old.stringModel
            || config.engine != old.engine || config.band != old.band {
            stringTracker = StringStateTracker(targets: config.targetsHz, parameters: config.stringModel)
            shownString = nil
        }
        if config.band != old.band {
            preprocessor.setCutoffs(highPassHz: config.band.highPassHz,
                                    lowPassHz: config.band.lowPassHz)
            smoother.reset()
            continuity.reset()   // a candidate from the old band means nothing now
        }
        if config.smoothing != old.smoothing || config.smootherWindow != old.smootherWindow {
            // Both are fixed at `PitchSmoother` init, so rebuild (history
            // dropped — a clean restart is what we want when smoothing changes).
            smoother = Self.makeSmoother(config)
        }
        if config.dropoutFrames != old.dropoutFrames
            || config.continuityAgreementCents != old.continuityAgreementCents {
            continuity = Self.makeContinuity(config)
        }
        if config.referencePitch != old.referencePitch {
            calculator = PitchCalculator(referenceA: config.referencePitch)
        }
        preprocessor.isEnabled = config.preprocessingEnabled
    }

    private static func makeSmoother(_ config: PitchTrackerConfig) -> PitchSmoother {
        PitchSmoother(windowSize: config.smootherWindow, emaFactor: config.smoothing)
    }

    private static func makeContinuity(_ config: PitchTrackerConfig) -> PitchContinuity {
        PitchContinuity(dropoutFrames: config.dropoutFrames,
                        agreementCents: config.continuityAgreementCents)
    }
}
