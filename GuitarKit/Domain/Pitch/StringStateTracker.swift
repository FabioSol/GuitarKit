//
//  StringStateTracker.swift
//  GuitarKit
//
//  The PROBABILISTIC string tracker for targeted mode: instead of asking each
//  frame "does this pass the gates?", it keeps a running belief about WHICH
//  STRING (if any) is ringing, and lets evidence pile up over frames.
//
//  THE MODEL (a hidden Markov model, run forward one frame at a time):
//
//    hidden state:  silence  |  string 1 ringing  |  …  |  string N ringing
//                   ("silence" = no target string — a voice or a TV may well
//                    be making sound)
//
//    transitions:   strings ring for seconds, so states are STICKY. Starting
//                   a string, or switching to another, becomes much more likely
//                   on a frame where the level jumps (a pluck).
//
//    evidence:      for each string, how much more likely is this frame if
//                   that string is ringing than if it isn't? (a log-likelihood
//                   ratio, "LLR"; silence is the 0 reference). Built from:
//                     • level and clarity — but only AGAINST a string (too
//                       quiet / too noisy): voices and TVs are loud and clear
//                       too, so they can't count FOR one;
//                     • harmonicity — one harmonic source vs a voice, a chord,
//                       clicks — counts both ways;
//                     • distance to the string's TARGET (the tuning is known);
//                     • STABILITY against the pitch this string had last frame
//                       (strings hold steady; speech glides);
//                     • PRESENCE: even when the detector latches onto a voice,
//                       do this string's own partials still stand out locally
//                       in the spectrum? That keeps it tracked underneath.
//
//    each frame:    belief(state) ∝ Σ belief_prev × transition × evidence
//                   (the "forward algorithm"); show string i when its belief
//                   passes a threshold.
//
//  It replaces the gated path's clarity/level gates, sustain hysteresis and
//  `PitchContinuity` — one model with a handful of understandable
//  probabilities instead of interacting thresholds.
//
//  Pure value logic: observations in (with two small closures that query the
//  frame's spectrum), decisions out. No audio, no clocks — tested with
//  scripted frames.
//

import Foundation

nonisolated struct StringStateTracker {

    // MARK: Parameters

    /// The model's knobs. Probabilities are PER FRAME (~0.1 s).
    ///
    /// Values from an Optuna search on generated clips (PitchBench/tune.py
    /// `--space probabilistic`, trial 525 of 600), checked on held-out
    /// generated clips and on real recordings the search never saw — see
    /// PitchBench/TUNING-hmm.md. What they say about a plucked string:
    /// strings almost only START on a pluck (0.25% per frame otherwise, 78% on
    /// a level jump), hold their pitch within ~15¢ between frames, sit within
    /// ~1 semitone of their target, and stop showing quickly once evidence
    /// fades (15% per frame) — while a string is only SHOWN once the model is
    /// 90% sure.
    struct Parameters: Equatable {
        /// A level jump this big (dB, frame to frame) counts as a pluck.
        var onsetRiseDB: Float = 3.4
        /// silence → some string, per frame, without / with a pluck.
        var startProbability: Float = 0.0025
        var onsetStartProbability: Float = 0.78
        /// ringing → silence, per frame.
        var stopProbability: Float = 0.15
        /// one string → another, per frame, without / with a pluck.
        var switchProbability: Float = 0.04
        var onsetSwitchProbability: Float = 0.04

        /// How far (cents, one standard deviation) a string may sit from its
        /// target and still look like that string.
        var detuneCents: Float = 93
        /// How much a ringing string's pitch may move between frames (cents).
        var stabilityCents: Float = 15
        /// Weight of the stability evidence (1 = full strength).
        var stabilityWeight: Float = 0.82
        /// Evidence cost of reading an OCTAVE of the target instead.
        var octavePenalty: Float = 2

        /// Soft versions of the old gates: evidence = slope × (value − midpoint).
        var clarityMidpoint: Float = 0.34
        var claritySlope: Float = 8
        /// Capped at 0.72 during the search — the 25th percentile of REAL
        /// string frames (generated strings score higher; see PitchBench/README).
        var harmonicityMidpoint: Float = 0.72
        var harmonicitySlope: Float = 25
        var levelMidpointDB: Float = -66
        var levelSlopeDB: Float = 4            // dB per unit of evidence
        /// Evidence when the detector finds no pitch at all.
        var missEvidence: Float = -0.28

        /// "Still there" evidence from the string's own partials (salience).
        var salienceMidpoint: Float = 0.51
        var salienceSlope: Float = 8
        /// Presence is weaker evidence than a direct detection.
        var presenceBias: Float = -0.97

        /// Show a string once its belief reaches this.
        var showThreshold: Float = 0.9
    }

    // MARK: Per-frame input / output

    /// What one frame tells us.
    struct Observation {
        /// In-band level, dBFS.
        var levelDB: Float
        /// The detector's best pitch this frame (nil = none found).
        var candidate: Candidate?
        /// Salience (0…1) of a given pitch's partials in this frame's spectrum.
        var salience: (Float) -> Float? = { _ in nil }
        /// Re-measure a pitch from this frame's spectrum near a guess.
        var refine: (Float) -> Float? = { _ in nil }

        struct Candidate {
            var frequency: Float
            var clarity: Float
            var harmonicity: Float
        }
    }

    enum Decision: Equatable {
        case silent
        /// String `index` (into the targets) is ringing at `frequency` Hz,
        /// believed with `probability`.
        case ringing(index: Int, frequency: Float, probability: Float)
    }

    // MARK: State

    let targets: [Float]
    let parameters: Parameters

    /// Belief per state: [silence, string 0, string 1, …]. Sums to 1.
    private(set) var belief: [Float]
    /// The pitch each string last had (nil = not seen recently).
    private var trackedPitch: [Float?]
    /// Frames since each string was last believed (to forget stale pitches).
    private var unbelievedFrames: [Int]
    private var previousLevelDB: Float?
    /// log(band width in cents) — the "anywhere in the band" alternative.
    private let logBandCents: Float

    /// - Parameter targets: the strings' target frequencies (Hz), capo-shifted.
    init(targets: [Double], parameters: Parameters = Parameters()) {
        self.targets = targets.map(Float.init)
        self.parameters = parameters
        belief = [1] + Array(repeating: 0, count: targets.count)
        trackedPitch = Array(repeating: nil, count: targets.count)
        unbelievedFrames = Array(repeating: 0, count: targets.count)
        // The band a pitch could appear in: a little below the lowest string
        // to a little above the highest (as `DetectionBand` does).
        let low = (targets.min() ?? 80) * pow(2, -5.0 / 12)
        let high = (targets.max() ?? 330) * pow(2, 3.0 / 12)
        logBandCents = Float(log(max(1200 * log2(high / low), 100)))
    }

    mutating func reset() {
        self = StringStateTracker(targets: targets.map(Double.init), parameters: parameters)
    }

    // MARK: One frame

    mutating func step(_ frame: Observation) -> Decision {
        let p = parameters
        let n = targets.count
        guard n > 0 else { return .silent }

        // A pluck-like level jump makes starting/switching strings likely.
        let onset = previousLevelDB.map { frame.levelDB - $0 >= p.onsetRiseDB } ?? false
        previousLevelDB = frame.levelDB

        // 1) TRANSITION: where could we be now, before looking at the evidence?
        let start = onset ? p.onsetStartProbability : p.startProbability
        let change = n > 1 ? (onset ? p.onsetSwitchProbability : p.switchProbability) : 0
        let ringingTotal = belief.dropFirst().reduce(0, +)
        var prior = [Float](repeating: 0, count: n + 1)
        prior[0] = belief[0] * (1 - start) + ringingTotal * p.stopProbability
        for i in 0..<n {
            let others = ringingTotal - belief[i + 1]
            prior[i + 1] = belief[0] * start / Float(n)
                + belief[i + 1] * (1 - p.stopProbability - change)
                + (n > 1 ? others * change / Float(n - 1) : 0)
        }

        // 2) EVIDENCE for each string (silence is the 0 reference).
        var evidence = [Float](repeating: 0, count: n + 1)
        var heard = [Float?](repeating: nil, count: n)
        // LEVEL can only count AGAINST a string: a quiet frame is unlikely to
        // be a ringing string, but a loud one is just as likely to be a voice
        // or a TV ("silence" means "no target string", not "no sound").
        let level = clamp((frame.levelDB - p.levelMidpointDB) / p.levelSlopeDB, -4, 0)
        for i in 0..<n {
            var best = -Float.infinity
            if let c = frame.candidate {
                let (llr, frequency) = candidateEvidence(c, string: i, level: level)
                best = llr
                heard[i] = frequency
            } else {
                best = p.missEvidence + min(level, 0)
            }
            // PRESENCE: is this string still sounding underneath whatever the
            // detector picked? Only for strings we've been following.
            if let pitch = trackedPitch[i], let salience = frame.salience(pitch) {
                let llr = level + clamp(p.salienceSlope * (salience - p.salienceMidpoint), -4, 4)
                    + p.presenceBias
                if llr > best {
                    best = llr
                    heard[i] = frame.refine(pitch) ?? pitch
                }
            }
            evidence[i + 1] = best
        }

        // 3) COMBINE (in logs, so strong evidence can't overflow) and normalize.
        let logs = zip(prior, evidence).map { log(max($0, 1e-9)) + $1 }
        let top = logs.max() ?? 0
        let weights = logs.map { exp($0 - top) }
        let total = weights.reduce(0, +)
        belief = weights.map { max($0 / total, 1e-6) }          // never fully rule a state out
        let sum = belief.reduce(0, +)
        belief = belief.map { $0 / sum }

        // 4) REMEMBER each believed string's pitch; forget long-unbelieved ones.
        for i in 0..<n {
            if belief[i + 1] > 0.3, let f = heard[i] {
                trackedPitch[i] = f
                unbelievedFrames[i] = 0
            } else {
                unbelievedFrames[i] += 1
                if unbelievedFrames[i] > 10 { trackedPitch[i] = nil }
            }
        }

        // 5) DECIDE.
        guard let index = (0..<n).max(by: { belief[$0 + 1] < belief[$1 + 1] }),
              belief[index + 1] >= p.showThreshold,
              let frequency = heard[index] ?? trackedPitch[index] else { return .silent }
        return .ringing(index: index, frequency: frequency, probability: belief[index + 1])
    }

    /// Evidence that the detected candidate IS string `i` — and the pitch it
    /// implies for that string (an octave reading is folded back).
    private func candidateEvidence(_ c: Observation.Candidate, string i: Int,
                                   level: Float) -> (Float, Float) {
        let p = parameters
        // Closest of: the reading itself, an octave up, an octave down.
        let options: [(frequency: Float, penalty: Float)] = [
            (c.frequency, 0), (c.frequency * 2, p.octavePenalty), (c.frequency / 2, p.octavePenalty),
        ]
        let (frequency, penalty) = options.min {
            abs(cents($0.frequency, targets[i])) + $0.penalty * 100
                < abs(cents($1.frequency, targets[i])) + $1.penalty * 100
        }!

        // TARGET: a bell curve around the string's target, against "anywhere
        // in the band" (a uniform spread over the band's width in cents).
        let d = cents(frequency, targets[i]) / p.detuneCents
        let target = -0.5 * d * d - log(p.detuneCents * 2.5066) + logBandCents - penalty

        // STABILITY: a bell curve around last frame's pitch for this string
        // (mixed with a little "anything", so one outlier frame isn't fatal).
        var stability: Float = 0
        if let previous = trackedPitch[i] {
            let s = cents(frequency, previous) / p.stabilityCents
            let bell = exp(-0.5 * s * s) / (p.stabilityCents * 2.5066)
            let uniform = exp(-logBandCents)
            stability = p.stabilityWeight * log((0.8 * bell + 0.2 * uniform) / uniform)
        }

        // CLARITY, like level, only counts against: voices and instruments are
        // clearly periodic too. HARMONICITY is the real discriminator (one
        // harmonic source vs a voice/chord/clicks), so it counts both ways.
        let clarity = clamp(p.claritySlope * (c.clarity - p.clarityMidpoint), -4, 0)
        let harmonicity = clamp(p.harmonicitySlope * (c.harmonicity - p.harmonicityMidpoint), -4, 4)
        return (level + clarity + harmonicity + target + stability, frequency)
    }

    private func cents(_ a: Float, _ b: Float) -> Float {
        guard a > 0, b > 0 else { return .infinity }
        return 1200 * log2(a / b)
    }

    private func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float { min(max(x, lo), hi) }
}
