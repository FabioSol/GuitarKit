//
//  PitchBenchmark.swift
//  GuitarKitTests
//
//  A MEASURING STICK for the pitch tracker. Unit tests answer "is this case
//  right?"; the benchmark answers "how good is the tuner overall, and did my
//  change make it better or worse?" — across many clips: soft and hard plucks,
//  quiet rooms, fans, other instruments, voices, clicks, a phone playing video.
//
//  A clip is replayed through `PitchTracker` window by window, exactly the way
//  the live tuner feeds it, and scored on what a player actually feels:
//
//    • detected  — did the right note (±50¢) ever show up?
//    • latency   — from the note becoming audible to the first correct reading
//    • coverage  — what fraction of the AUDIBLE note had a correct reading
//                  (low = the needle disappears while the string still rings)
//    • sustain   — seconds of correct readings
//    • jitter    — mean |Δcents| between consecutive readings (needle wobble)
//    • median ¢  — where the string actually sat (recorded strings are rarely
//                  exactly in tune, so this is a bias, not an error)
//    • wrong     — readings more than 50¢ from the labelled note — usually the
//                  tracker latching onto the INTERFERENCE (a voice, a chord…)
//    • false     — seconds of readings when nothing was plucked (should be 0)
//
//  WHEN IS A NOTE "AUDIBLE"? For generated clips we know the truth: we have
//  the clean string signal and the interference separately, so a window
//  counts while the string is at least as loud as the interference INSIDE the
//  tracker's band (in-band SNR ≥ 0 dB). Recorded clips only have the mix, so
//  there it's estimated: in-band level ≥ 6 dB over the room's floor.
//
//  Clips come from two places: real recordings made with the Tuner Lab
//  (`PitchBench/recordings/`, see its README) and generated ones
//  (`syntheticClips`, built from `Interference`).
//

import Foundation
import AVFoundation
// `PitchBench/run.sh` compiles this file straight into a Mac command-line
// tool alongside the app's pitch sources, where there's no module to import.
#if !PITCH_BENCH_CLI
@testable import GuitarKit
#endif

// MARK: - Clips

struct BenchClip {
    let name: String
    let samples: [Float]
    let sampleRate: Double
    /// The window size the live tuner received (replayed identically).
    let windowFrames: Int
    /// The labelled note's frequency, or `nil` when nothing was plucked.
    let expectedHz: Double?
    let pluck: String?
    /// What else was audible ("quiet room", "speech @ −40 dB", "tv"…).
    let background: String
    /// Band + reference pitch in force when the clip was made. The tracker's
    /// other knobs come from the config under test.
    let band: DetectionBand
    let referencePitch: ReferencePitch
    /// Generated clips only: the clean string signal on its own (the rest of
    /// `samples` is interference), so audibility can be judged exactly.
    var target: [Float]? = nil
    /// The lowest and highest string of the tuning, so a parameter search can
    /// re-derive `band` with different margins. `nil` = keep `band` as is.
    var tuningRangeHz: ClosedRange<Double>? = nil
    /// The tuning's string targets (Hz), when known — the probabilistic
    /// engine needs them. `nil` = treat as chromatic (it falls back to gated).
    var targetsHz: [Double]? = nil
}

// MARK: - Tunable parameters

/// Every knob a parameter search may vary, all optional (`nil` = keep the
/// default). Decoded from JSON by the `serve` mode of `PitchBench/run.sh`.
struct TunableParams: Codable, Equatable {
    var algorithm: String?
    var clarityThreshold: Float?
    var levelGateDB: Float?
    var smoothing: Float?
    var preprocessingEnabled: Bool?
    var smootherWindow: Int?
    var sustainClarityFactor: Float?
    var sustainLevelReliefDB: Float?
    var dropoutFrames: Int?
    var continuityAgreementCents: Float?
    var harmonicGate: Float?
    var harmonicSustainFactor: Float?
    var harmonicCount: Int?
    var engine: String?
    // Probabilistic engine (StringStateTracker.Parameters)
    var onsetRiseDB: Float?
    var startProbability: Float?
    var onsetStartProbability: Float?
    var stopProbability: Float?
    var switchProbability: Float?
    var onsetSwitchProbability: Float?
    var detuneCents: Float?
    var stabilityCents: Float?
    var stabilityWeight: Float?
    var hmmClarityMidpoint: Float?
    var hmmHarmonicityMidpoint: Float?
    var hmmHarmonicitySlope: Float?
    var hmmLevelMidpointDB: Float?
    var missEvidence: Float?
    var salienceMidpoint: Float?
    var presenceBias: Float?
    var showThreshold: Float?
    var flatMarginSemitones: Double?
    var sharpMarginSemitones: Double?
    var harmonicHeadroom: Double?

    func apply(to config: inout PitchTrackerConfig) {
        if let algorithm, let value = PitchAlgorithm(rawValue: algorithm) { config.algorithm = value }
        if let clarityThreshold { config.clarityThreshold = clarityThreshold }
        if let levelGateDB { config.levelGateDB = levelGateDB }
        if let smoothing { config.smoothing = smoothing }
        if let preprocessingEnabled { config.preprocessingEnabled = preprocessingEnabled }
        if let smootherWindow { config.smootherWindow = smootherWindow }
        if let sustainClarityFactor { config.sustainClarityFactor = sustainClarityFactor }
        if let sustainLevelReliefDB { config.sustainLevelReliefDB = sustainLevelReliefDB }
        if let dropoutFrames { config.dropoutFrames = dropoutFrames }
        if let continuityAgreementCents { config.continuityAgreementCents = continuityAgreementCents }
        if let harmonicGate { config.harmonicGate = harmonicGate }
        if let harmonicSustainFactor { config.harmonicSustainFactor = harmonicSustainFactor }
        if let harmonicCount { config.harmonicCount = harmonicCount }
        if let engine, let value = PitchEngine(rawValue: engine) { config.engine = value }
        var m = config.stringModel
        if let onsetRiseDB { m.onsetRiseDB = onsetRiseDB }
        if let startProbability { m.startProbability = startProbability }
        if let onsetStartProbability { m.onsetStartProbability = onsetStartProbability }
        if let stopProbability { m.stopProbability = stopProbability }
        if let switchProbability { m.switchProbability = switchProbability }
        if let onsetSwitchProbability { m.onsetSwitchProbability = onsetSwitchProbability }
        if let detuneCents { m.detuneCents = detuneCents }
        if let stabilityCents { m.stabilityCents = stabilityCents }
        if let stabilityWeight { m.stabilityWeight = stabilityWeight }
        if let hmmClarityMidpoint { m.clarityMidpoint = hmmClarityMidpoint }
        if let hmmHarmonicityMidpoint { m.harmonicityMidpoint = hmmHarmonicityMidpoint }
        if let hmmHarmonicitySlope { m.harmonicitySlope = hmmHarmonicitySlope }
        if let hmmLevelMidpointDB { m.levelMidpointDB = hmmLevelMidpointDB }
        if let missEvidence { m.missEvidence = missEvidence }
        if let salienceMidpoint { m.salienceMidpoint = salienceMidpoint }
        if let presenceBias { m.presenceBias = presenceBias }
        if let showThreshold { m.showThreshold = showThreshold }
        config.stringModel = m
    }

    var margins: DetectionBand.Margins {
        var m = DetectionBand.Margins()
        if let flatMarginSemitones { m.flatSemitones = flatMarginSemitones }
        if let sharpMarginSemitones { m.sharpSemitones = sharpMarginSemitones }
        if let harmonicHeadroom { m.harmonicHeadroom = harmonicHeadroom }
        return m
    }

    /// The band to use for a clip: re-derived with these margins when the clip
    /// knows its tuning's range, otherwise the band it was recorded with.
    func band(for clip: BenchClip) -> DetectionBand {
        guard let range = clip.tuningRangeHz else { return clip.band }
        return DetectionBand.around(lowestHz: range.lowerBound, highestHz: range.upperBound,
                                    margins: margins) ?? clip.band
    }
}

/// One number per goal, over a SET of clips — what a parameter search
/// optimizes. All rates are 0…1.
struct BenchScore: Codable {
    /// Mean share of each audible note that had a correct reading. ↑
    var coverage: Double
    /// Share of all windows (in plucked clips) showing a WRONG note. ↓
    var wrongRate: Double
    /// Share of windows showing ANY note when nothing was plucked. ↓
    var falseRate: Double
    /// Share of plucked clips where the right note showed up at all. ↑
    var detectionRate: Double
    /// Median ms from audible to first correct reading. ↓
    var medianLatencyMs: Double
    /// Mean needle wobble between consecutive correct readings, cents. ↓
    var jitterCents: Double
    var clips: Int
}

/// The recorder's `.json` sidecar (mirror of `PitchClipRecorder.Metadata` —
/// decoded independently so the test target doesn't depend on DEBUG-only UI).
private struct RecordedClipMetadata: Decodable {
    let note: String?
    let expectedHz: Double?
    let pluck: String?
    let background: String
    let referenceA: Double
    let bandMinHz: Double
    let bandMaxHz: Double
    let highPassHz: Double
    let lowPassHz: Double
    let windowFrames: Int
    let targetsHz: [Double]?
}

// MARK: - Results

struct ClipResult {
    let clip: BenchClip
    let detected: Bool
    let latencyMs: Double?
    let coverage: Double?
    let sustainSeconds: Double
    let jitterCents: Double?
    let medianCents: Double?
    /// Readings > 50¢ off the labelled note (or ANY reading, when nothing was plucked).
    let wrongReadings: Int
    /// The notes those wrong readings named, most frequent first ("C#3", "A2"…).
    let wrongNotes: [String]
    let falseSeconds: Double
    /// How many windows the clip was replayed as.
    let windows: Int
}

// MARK: - The harness

enum PitchBenchmark {

    /// Readings further than this from the labelled note count as wrong.
    static let correctWindowCents = 50.0

    /// Replay one clip through a fresh tracker.
    static func run(_ clip: BenchClip, params: TunableParams = TunableParams()) -> ClipResult {
        var config = PitchTrackerConfig(band: params.band(for: clip), referencePitch: clip.referencePitch)
        // Clips made in TARGETED mode (they know their tuning) get what the app
        // runs in targeted mode — so these numbers describe the real tuner.
        if clip.tuningRangeHz != nil { config.harmonicGate = PitchTrackerConfig.targetedModeHarmonicGate }
        if let targets = clip.targetsHz { config.targetsHz = targets }
        params.apply(to: &config)
        var tracker = PitchTracker(config: config)

        // In-band level meters: independent band-passes with the clip's
        // DEFAULT band, so "audible" means the same thing whatever parameters
        // are under test (a search can't game it by narrowing the band).
        func meter() -> PitchPreprocessor {
            PitchPreprocessor(highPassHz: clip.band.highPassHz, lowPassHz: clip.band.lowPassHz)
        }
        var mixMeter = meter(), targetMeter = meter(), interferenceMeter = meter()

        let window = max(clip.windowFrames, 256)
        let windowSeconds = Double(window) / clip.sampleRate
        var readings: [PitchReading?] = []
        var mixLevels: [Float] = []
        var trueAudible: [Bool] = []
        var start = 0
        while start + window <= clip.samples.count {
            let range = start ..< start + window
            let frame = Array(clip.samples[range])
            readings.append(tracker.process(samples: frame, sampleRate: clip.sampleRate))
            mixLevels.append(AudioLevel.rms(of: mixMeter.process(frame, sampleRate: clip.sampleRate)))
            if let target = clip.target {
                let t = Array(target[range])
                let i = zip(frame, t).map { $0 - $1 }
                let tLevel = AudioLevel.rms(of: targetMeter.process(t, sampleRate: clip.sampleRate))
                let iLevel = AudioLevel.rms(of: interferenceMeter.process(i, sampleRate: clip.sampleRate))
                // SNR ≥ 0 dB in band (and above −100 dBFS, so digital silence
                // never counts as a note).
                trueAudible.append(tLevel >= max(iLevel, 1e-5))
            }
            start += window
        }

        // Nothing plucked: anything shown is a false reading.
        guard let expected = clip.expectedHz else {
            let shown = readings.compactMap { $0 }
            return ClipResult(clip: clip, detected: false, latencyMs: nil, coverage: nil,
                              sustainSeconds: 0, jitterCents: nil, medianCents: nil,
                              wrongReadings: shown.count, wrongNotes: topNotes(shown),
                              falseSeconds: Double(shown.count) * windowSeconds,
                              windows: readings.count)
        }

        let cents: [Double?] = readings.map { reading in
            reading.map { PitchCalculator.cents(from: $0.frequency, to: expected) }
        }
        let correct = cents.map { c in c.map { abs($0) <= correctWindowCents } ?? false }
        let wrong = zip(readings, cents).compactMap { r, c in
            c.map { abs($0) > correctWindowCents } == true ? r : nil
        }
        let correctCents = zip(cents, correct).compactMap { c, ok in ok ? c : nil }

        // Which windows held an audible note: the truth for generated clips;
        // for recordings, in-band level ≥ 6 dB over the room's floor (the
        // quietest 10% of windows — clips start with a moment before the pluck).
        let audible: [Bool]
        if clip.target != nil {
            audible = trueAudible
        } else {
            let threshold = max(percentile(mixLevels, 0.1) * 2, 1e-7)     // +6 dB, never 0
            audible = mixLevels.map { $0 >= threshold }
        }
        let audibleCount = audible.filter { $0 }.count
        let onset = audible.firstIndex(of: true)
        let firstCorrect = correct.firstIndex(of: true)

        var latencyMs: Double?
        var coverage: Double?
        if let onset, audibleCount > 0 {
            // The reading appears when its window ENDS — hence the +1.
            latencyMs = firstCorrect.map { Double($0 + 1 - onset) * windowSeconds * 1000 }
            coverage = Double(zip(audible, correct).filter { $0 && $1 }.count) / Double(audibleCount)
        }

        var jitter: Double?
        if correctCents.count >= 2 {
            let deltas = zip(correctCents.dropFirst(), correctCents).map { abs($0 - $1) }
            jitter = deltas.reduce(0, +) / Double(deltas.count)
        }

        return ClipResult(
            clip: clip,
            detected: firstCorrect != nil,
            latencyMs: latencyMs,
            coverage: coverage,
            sustainSeconds: Double(correct.filter { $0 }.count) * windowSeconds,
            jitterCents: jitter,
            medianCents: correctCents.isEmpty ? nil : percentile(correctCents, 0.5),
            wrongReadings: wrong.count,
            wrongNotes: topNotes(wrong),
            falseSeconds: 0,
            windows: readings.count
        )
    }

    /// Summarize results into one number per goal.
    static func score(_ results: [ClipResult]) -> BenchScore {
        let notes = results.filter { $0.clip.expectedHz != nil }
        let alone = results.filter { $0.clip.expectedHz == nil }
        let coverage = notes.compactMap(\.coverage)
        let latencies = notes.compactMap(\.latencyMs)
        let jitters = notes.compactMap(\.jitterCents)
        func ratio(_ part: Int, _ whole: Int) -> Double { whole > 0 ? Double(part) / Double(whole) : 0 }
        return BenchScore(
            coverage: coverage.isEmpty ? 0 : coverage.reduce(0, +) / Double(coverage.count),
            wrongRate: ratio(notes.map(\.wrongReadings).reduce(0, +), notes.map(\.windows).reduce(0, +)),
            falseRate: ratio(alone.map(\.wrongReadings).reduce(0, +), alone.map(\.windows).reduce(0, +)),
            detectionRate: ratio(notes.filter(\.detected).count, notes.count),
            medianLatencyMs: latencies.isEmpty ? 0 : percentile(latencies, 0.5),
            jitterCents: jitters.isEmpty ? 0 : jitters.reduce(0, +) / Double(jitters.count),
            clips: results.count
        )
    }

    /// The up-to-3 most frequent note names among some readings.
    private static func topNotes(_ readings: [PitchReading]) -> [String] {
        let counts = Dictionary(grouping: readings, by: \.note.name).mapValues(\.count)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3).map(\.key)
    }

    // MARK: Loading recordings

    /// `<repo>/PitchBench/`, found relative to this source file so it works
    /// from Xcode and the command line alike.
    static var benchDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Benchmark/
            .deletingLastPathComponent()   // Pitch/
            .deletingLastPathComponent()   // GuitarKitTests/
            .deletingLastPathComponent()   // repo root
            .appending(path: "PitchBench", directoryHint: .isDirectory)
    }

    /// Every `.wav` + `.json` pair in `PitchBench/recordings/`.
    static func loadRecordings() throws -> [BenchClip] {
        let dir = benchDirectory.appending(path: "recordings", directoryHint: .isDirectory)
        let wavs = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try wavs.map { wav in
            let json = wav.deletingPathExtension().appendingPathExtension("json")
            let meta = try JSONDecoder().decode(RecordedClipMetadata.self, from: Data(contentsOf: json))
            let (samples, rate) = try readMono(wav)
            return BenchClip(
                name: wav.deletingPathExtension().lastPathComponent,
                samples: samples, sampleRate: rate,
                windowFrames: meta.windowFrames,
                expectedHz: meta.expectedHz,
                pluck: meta.pluck, background: meta.background,
                band: DetectionBand(minFrequencyHz: meta.bandMinHz, maxFrequencyHz: meta.bandMaxHz,
                                    highPassHz: meta.highPassHz, lowPassHz: meta.lowPassHz),
                referencePitch: ReferencePitch(hertz: meta.referenceA),
                tuningRangeHz: tuningRange(bandMinHz: meta.bandMinHz, bandMaxHz: meta.bandMaxHz),
                targetsHz: meta.targetsHz
            )
        }
    }

    /// Recover the tuning's lowest/highest string from a recorded band by
    /// undoing the DEFAULT margins it was derived with. `nil` for the full
    /// band (chromatic / editor capture) or a floor-clamped band, where the
    /// targets can't be recovered.
    private static func tuningRange(bandMinHz: Double, bandMaxHz: Double) -> ClosedRange<Double>? {
        let defaults = DetectionBand.Margins()
        guard bandMinHz > DetectionBand.full.minFrequencyHz + 0.01 || bandMaxHz < DetectionBand.full.maxFrequencyHz - 0.01,
              bandMinHz > 20.01 else { return nil }
        let lowest = bandMinHz * pow(2, defaults.flatSemitones / 12)
        let highest = bandMaxHz * pow(2, -defaults.sharpSemitones / 12)
        return lowest <= highest ? lowest...highest : nil
    }

    private static func readMono(_ url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        return (samples, file.processingFormat.sampleRate)
    }

    // MARK: Generated clips

    /// The strings each condition is tested on: the lowest (hardest), plus a
    /// spread up the neck. Standard guitar tuning supplies the band.
    /// Standard guitar tuning at A4 = 440 Hz, low E to high E.
    static let standardGuitarHz = [82.4068892282175, 110.0, 146.8323839587038, 195.99771799087463, 246.94165062806206, 329.6275569128699]

    static let syntheticStrings: [(note: String, hz: Double)] =
        [("E2", 82.41), ("A2", 110.0), ("G3", 196.0), ("E4", 329.63)]

    /// Peak amplitudes of the pluck: hard ≈ −12 dBFS, medium ≈ −30, soft ≈ −46.
    static let syntheticPlucks: [(name: String, peak: Float)] =
        [("soft", 0.005), ("medium", 0.03), ("hard", 0.25)]

    /// Every interference kind at every level (the quiet room once).
    static var syntheticConditions: [(kind: Interference, levelDBFS: Double?)] {
        Interference.allCases.flatMap { kind -> [(Interference, Double?)] in
            kind == .quietRoom ? [(kind, nil)] : Interference.levelsDBFS.map { (kind, $0) }
        }
    }

    static func label(_ kind: Interference, _ level: Double?) -> String {
        level.map { "\(kind.rawValue) @ \(Int($0)) dB" } ?? kind.rawValue
    }

    /// Plucked strings under every interference condition, plus each
    /// condition alone (nothing plucked — anything shown is a false reading).
    /// Deterministic: same clips on every run.
    /// - Parameter seedBase: different bases give the same conditions with
    ///   different random details — a parameter search tunes on one base and
    ///   checks on another, so it can't just memorize these exact clips.
    static func syntheticClips(seedBase: UInt64 = 1) -> [BenchClip] {
        let rate = 44_100.0
        let band = DetectionBand.around(targets: [82.41, 110, 146.83, 196, 246.94, 329.63]
            .enumerated().map { i, hz in
                PitchTarget(note: Note(pitchClass: .a, octave: 4), frequencyHz: hz, stringIndex: i)
            }) ?? .full
        let preRoll = Int(0.5 * rate), noteLength = Int(2.5 * rate), total = preRoll + noteLength

        var clips: [BenchClip] = []
        var seed: UInt64 = seedBase &* 100_003
        for (kind, level) in syntheticConditions {
            let background = label(kind, level)

            func room(avoidingHz: Double?) -> [Float] {
                seed &+= 1
                var rng = SeededRandom(seed: seed &* 7)
                var mix = (0..<total).map { _ in rng.gaussian() * Interference.roomHissRMS }
                if let level {
                    let sound = kind.render(count: total, sampleRate: rate, levelDBFS: level,
                                            seed: seed, avoidingHz: avoidingHz)
                    for i in 0..<total { mix[i] += sound[i] }
                }
                return mix
            }

            for (note, hz) in syntheticStrings {
                for (pluck, peak) in syntheticPlucks {
                    let target = pluckedString(hz: hz, peak: peak, preRoll: preRoll,
                                               length: noteLength, sampleRate: rate, seed: seed)
                    let interference = room(avoidingHz: hz)
                    clips.append(BenchClip(
                        name: "\(note) \(pluck) · \(background)",
                        samples: zip(target, interference).map(+), sampleRate: rate,
                        windowFrames: 4_096, expectedHz: hz, pluck: pluck,
                        background: background, band: band, referencePitch: .standard,
                        target: target, tuningRangeHz: 82.41...329.63,
                        targetsHz: standardGuitarHz))
                }
            }
            clips.append(BenchClip(
                name: "nothing plucked · \(background)",
                samples: room(avoidingHz: nil), sampleRate: rate, windowFrames: 4_096,
                expectedHz: nil, pluck: nil, background: background,
                band: band, referencePitch: .standard, tuningRangeHz: 82.41...329.63,
                targetsHz: standardGuitarHz))
        }
        return clips
    }

    /// CLEAN, STEADY TONES across the guitar's range — pure sines and
    /// harmonic tones, in a quiet room. Real strings always have harmonics,
    /// but chromatic mode must also name near-pure tones (a whistle, a tuning
    /// fork), and a parameter search that only ever sees harmonic sounds will
    /// happily pick an algorithm that fails on them. These guard that.
    static func cleanTones() -> [BenchClip] {
        let rate = 44_100.0
        let band = DetectionBand.around(lowestHz: 82.41, highestHz: 329.63) ?? .full
        let length = 4_096 * 12
        var clips: [BenchClip] = []
        for (kind, partials) in [("pure sine", 1), ("harmonic tone", 6)] {
            var hz = 80.0
            var seed: UInt64 = 77
            while hz <= 340 {
                var tone = [Float](repeating: 0, count: length)
                for k in 1...partials {
                    let step = 2 * Double.pi * hz * Double(k) / rate
                    let amplitude = 0.1 / Double(k)
                    for i in 0..<length { tone[i] += Float(amplitude * sin(step * Double(i))) }
                }
                seed &+= 1
                let hiss = gaussianNoise(count: length, rms: Interference.roomHissRMS, seed: seed)
                clips.append(BenchClip(
                    name: "\(kind) \(String(format: "%.1f", hz)) Hz",
                    samples: zip(tone, hiss).map(+), sampleRate: rate, windowFrames: 4_096,
                    expectedHz: hz, pluck: nil, background: kind,
                    band: band, referencePitch: .standard,
                    target: tone, tuningRangeHz: 82.41...329.63))
                hz *= pow(2, 73.0 / 1200)        // ~¾-semitone steps, off the note grid
            }
        }
        return clips
    }

    /// A clean plucked string: silence for `preRoll`, then a 15 ms pick
    /// transient and a decaying, slightly inharmonic, weak-fundamental tone.
    private static func pluckedString(hz: Double, peak: Float, preRoll: Int, length: Int,
                                      sampleRate rate: Double, seed: UInt64) -> [Float] {
        var out = [Float](repeating: 0, count: preRoll + length)
        let tone = Signal.pluckedGuitarNote(fundamental: hz, sampleRate: rate,
                                            count: length, decayTime: 1.0)
        let tonePeak = tone.map(abs).max() ?? 1
        for i in tone.indices { out[preRoll + i] = tone[i] / tonePeak * peak }
        var rng = SeededRandom(seed: seed &* 31)
        for i in 0..<Int(0.015 * rate) {
            out[preRoll + i] += 0.3 * peak * rng.gaussian() * Float(exp(-Double(i) / (0.004 * rate)))
        }
        return out
    }

    /// Zero-mean, roughly Gaussian white noise at a given RMS.
    static func gaussianNoise(count: Int, rms: Float, seed: UInt64) -> [Float] {
        var rng = SeededRandom(seed: seed)
        return (0..<count).map { _ in rng.gaussian() * rms }
    }

    // MARK: Running everything

    /// Run every recorded and generated clip with the given engine, write
    /// `PitchBench/RESULTS.md` (gated, the app's default) or
    /// `RESULTS-probabilistic.md`, and return the report.
    @discardableResult
    static func writeResults(engine: PitchEngine = PitchTrackerConfig().engine) throws -> String {
        let params = TunableParams(engine: engine.rawValue)
        let recorded = try loadRecordings().map { run($0, params: params) }
        let synthetic = syntheticClips().map { run($0, params: params) }

        let config = PitchTrackerConfig()
        let engineNote = engine == .probabilistic
            ? "the PROBABILISTIC engine (`StringStateTracker`, default parameters) in targeted mode"
            : "the GATED engine in targeted mode — harmonic check \(PitchTrackerConfig.targetedModeHarmonicGate)"
        var md = """
        # Pitch benchmark results — \(engine.rawValue) engine

        Generated by `PitchBench/run.sh` / `PitchBenchmarkTests` — don't edit by \
        hand. Under test: \(engineNote). Front end: \
        algorithm `\(config.algorithm.rawValue)`, \
        clarity gate \(config.clarityThreshold), level gate \(Int(config.levelGateDB)) dBFS, \
        smoothing \(config.smoothing), band-pass \(config.preprocessingEnabled ? "on" : "off"). \
        Each clip keeps the band and reference pitch it was recorded with.

        **Reading the columns:** *latency* = note audible → first correct reading; \
        *coverage* = share of the audible note with a correct reading on screen \
        (**—** = the string was never louder than the interference in the tracker's \
        band, so missing it isn't necessarily the tracker's fault); *wrong* = readings \
        > 50¢ off the plucked note — usually the tracker following the interference.


        """
        md += recorded.isEmpty
            ? "## Recorded clips\n\n_None yet — record some with the Tuner Lab (see PitchBench/README.md)._\n"
            : report(title: "Recorded clips (\(recorded.count))", results: recorded)
        md += "\n"
        md += report(title: "Generated clips (\(synthetic.count))", results: synthetic)

        try FileManager.default.createDirectory(at: benchDirectory, withIntermediateDirectories: true)
        let file = engine == PitchTrackerConfig().engine ? "RESULTS.md" : "RESULTS-\(engine.rawValue).md"
        try md.write(to: benchDirectory.appending(path: file), atomically: true, encoding: .utf8)
        return md
    }

    // MARK: Report

    /// A Markdown report: one row per background, one column per pluck
    /// strength; then what each background produced when nothing was plucked;
    /// then every clip.
    static func report(title: String, results: [ClipResult]) -> String {
        guard !results.isEmpty else { return "## \(title)\n\n_No clips._\n" }
        var md = "## \(title)\n\n"

        // Backgrounds in first-seen order (generation order for synthetic).
        var backgrounds: [String] = []
        for r in results where !backgrounds.contains(r.clip.background) {
            backgrounds.append(r.clip.background)
        }
        let plucks = ["soft", "medium", "hard"]
        let notes = results.filter { $0.clip.expectedHz != nil }

        md += "Each cell: **detected / clips · mean coverage · wrong readings**.\n\n"
        md += "| background | " + plucks.joined(separator: " | ") + " | median latency |\n"
        md += "|---|" + plucks.map { _ in ":---:|" }.joined() + "---:|\n"
        for background in backgrounds {
            let row = notes.filter { $0.clip.background == background }
            guard !row.isEmpty else { continue }
            md += "| \(background) | "
            for pluck in plucks {
                let cell = row.filter { $0.clip.pluck == pluck }
                guard !cell.isEmpty else { md += "— | "; continue }
                let coverage = cell.compactMap(\.coverage)
                let wrong = cell.map(\.wrongReadings).reduce(0, +)
                md += "\(cell.filter(\.detected).count)/\(cell.count) · "
                md += coverage.isEmpty ? "—" : pct(coverage.reduce(0, +) / Double(coverage.count))
                md += wrong > 0 ? " · **\(wrong)✗**" : " · 0✗"
                md += " | "
            }
            let latencies = row.compactMap(\.latencyMs)
            md += latencies.isEmpty ? "— |\n" : "\(Int(percentile(latencies, 0.5))) ms |\n"
        }

        let alone = results.filter { $0.clip.expectedHz == nil }
        if !alone.isEmpty {
            md += "\n**Nothing plucked** — readings the background alone produced (should be none):\n\n"
            md += "| background | false readings | notes shown |\n|---|---:|---|\n"
            for r in alone {
                md += "| \(r.clip.background) | \(r.falseSeconds > 0 ? "**\(fmt(r.falseSeconds, 1)) s**" : "0 s") | "
                md += (r.wrongNotes.isEmpty ? "—" : r.wrongNotes.joined(separator: ", ")) + " |\n"
            }
        }

        md += "\n<details><summary>All clips</summary>\n\n"
        md += "| clip | detected | latency | coverage | sustain | jitter | median ¢ | wrong (notes) |\n"
        md += "|---|:---:|---:|---:|---:|---:|---:|---|\n"
        for r in results {
            md += "| \(r.clip.name) | "
            md += r.clip.expectedHz == nil ? "— | " : (r.detected ? "✓ | " : "✗ | ")
            md += r.latencyMs.map { "\(Int($0)) ms" } ?? "—"
            md += " | " + (r.coverage.map(pct) ?? "—")
            md += " | " + (r.clip.expectedHz == nil ? "\(fmt(r.falseSeconds, 1)) s false" : "\(fmt(r.sustainSeconds, 1)) s")
            md += " | " + (r.jitterCents.map { "\(fmt($0, 1))¢" } ?? "—")
            md += " | " + (r.medianCents.map { fmt($0, 1) } ?? "—")
            md += " | \(r.wrongReadings)"
            md += r.wrongNotes.isEmpty ? "" : " (\(r.wrongNotes.joined(separator: ", ")))"
            md += " |\n"
        }
        md += "\n</details>\n"
        return md
    }

    // MARK: Helpers

    static func percentile<T: BinaryFloatingPoint>(_ values: [T], _ p: Double) -> T {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }

    private static func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
    private static func fmt(_ x: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", x) }
}
