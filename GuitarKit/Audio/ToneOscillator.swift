//
//  ToneOscillator.swift
//  GuitarKit
//
//  The PURE math that synthesizes a warm, string-like tone, one Float sample at
//  a time. No AVFoundation, no hardware, no UI here — just trigonometry over a
//  running "phase". That separation is deliberate (same idea as `AudioLevel`):
//  this is the part we can unit-test deterministically (ask for a tone at a
//  known frequency → assert it's bounded, non-silent, and repeats at the right
//  period), while the noisy real-time playback bits live in `ToneGenerator`.
//
//  WHAT IS A "TONE", AND WHY HARMONICS?
//  A pure sine wave at, say, 110 Hz sounds thin and electronic — like a test
//  tone. A real plucked guitar string vibrates not only at its fundamental
//  frequency but also at integer multiples of it (2×, 3×, 4×… = the
//  "harmonics" / "overtones"), each a bit quieter than the last. Summing a
//  fundamental plus a few decaying harmonics gives the warm, recognizable
//  timbre your ear reads as "a string". This is the "harmonic-rich oscillator
//  for v1" the PRD calls for (Karplus–Strong is the future stretch goal).
//
//  HOW SAMPLE-BY-SAMPLE SYNTHESIS WORKS:
//  Digital audio is just a long list of numbers ("samples") played back at a
//  fixed rate (the SAMPLE RATE, e.g. 44 100 samples per second). To make a sine
//  wave we walk an angle ("phase") forward a little on every sample and take its
//  sine. How far we step each sample sets the pitch:
//
//      radians per sample = 2π · frequency / sampleRate
//
//  After `sampleRate / frequency` samples the phase has advanced a full 2π and
//  the wave repeats — that's exactly one cycle, i.e. the PERIOD in samples.
//

import Foundation

/// A namespace (empty `enum`, same trick as `AudioLevel`/`GKColor`) bundling the
/// pure tone-synthesis math. Callers write `ToneOscillator.samples(...)` etc.
/// Marked `enum` with no cases so it can never be instantiated — it's just a
/// home for these `static` functions and the small phase-walking generator.
enum ToneOscillator {

    // MARK: - Timbre definition (the harmonic recipe)

    /// The relative loudness of each harmonic, starting with the fundamental.
    ///
    /// Index 0 is the **fundamental** (1× the frequency) at full strength; each
    /// later entry is the next harmonic (2×, 3×, 4×, 5× the frequency) at a
    /// progressively smaller amplitude. The gentle roll-off (each overtone
    /// quieter than the one below it) is what makes the result sound "warm" and
    /// string-like rather than buzzy. These specific numbers are a taste choice,
    /// not physics — feel free to tweak for a brighter/darker tone.
    ///
    /// `static let` so the array is computed once and shared.
    static let harmonicAmplitudes: [Float] = [
        1.00,   // 1× — fundamental (the pitch you actually hear)
        0.50,   // 2× — octave above
        0.30,   // 3× — octave + fifth
        0.18,   // 4× — two octaves
        0.10,   // 5× — two octaves + major third
    ]

    /// The sum of all harmonic amplitudes — the worst-case peak if every
    /// harmonic happened to crest at the same instant. We divide the summed
    /// waveform by this so the output can never exceed `1.0` and clip (digital
    /// clipping = a harsh crackle when samples slam past full scale). Computed
    /// once from `harmonicAmplitudes` so it stays correct if you edit the recipe.
    static let normalization: Float = harmonicAmplitudes.reduce(0, +)

    // MARK: - Single-sample synthesis

    /// The value of our harmonic-rich waveform at one instant, given the
    /// fundamental's phase (its angle, in radians) at that instant.
    ///
    /// We add up `sin(n · phase) · amplitudeₙ` for each harmonic `n` (1, 2, 3…).
    /// Multiplying the phase by `n` makes that term oscillate `n` times faster —
    /// i.e. at `n ×` the fundamental frequency — which is exactly what a harmonic
    /// is. Finally we divide by `normalization` so the result is safely in
    /// `-1...1`.
    ///
    /// `phase` is in radians and may be any value; `sin` is periodic so it wraps
    /// naturally, but `ToneOscillator.Generator` keeps it small to avoid Float
    /// precision loss over long sustains.
    ///
    /// - Parameter phase: the fundamental's angle in radians at this sample.
    /// - Returns: one waveform sample, guaranteed within `-1.0 ... 1.0`.
    static func sample(atPhase phase: Float) -> Float {
        var value: Float = 0

        // `enumerated()` pairs each amplitude with its 0-based index; harmonic
        // number is index + 1 (so the fundamental is harmonic 1, not 0).
        for (index, amplitude) in harmonicAmplitudes.enumerated() {
            let harmonicNumber = Float(index + 1)
            value += sin(phase * harmonicNumber) * amplitude
        }

        // Scale down by the worst-case peak so we never clip past full scale.
        return value / normalization
    }

    /// How far (in radians) the fundamental's phase advances per output sample
    /// for a given pitch. This is the core pitch→step relationship:
    ///
    ///     radians per sample = 2π · frequency / sampleRate
    ///
    /// `Float.pi * 2` is one full turn (one cycle). Higher frequency → bigger
    /// step → the wave completes its cycle in fewer samples → higher pitch.
    ///
    /// - Parameters:
    ///   - frequencyHz: the pitch to synthesize, in Hertz.
    ///   - sampleRate: output samples per second (e.g. 44 100).
    /// - Returns: radians to add to the phase for each emitted sample.
    static func phaseStep(frequencyHz: Double, sampleRate: Double) -> Float {
        // Guard a non-positive sample rate so we never divide by zero. (A
        // zero/negative frequency is allowed and simply yields a flat 0 Hz "DC"
        // signal — silence — which is harmless.)
        guard sampleRate > 0 else { return 0 }
        return Float(2.0 * Double.pi * frequencyHz / sampleRate)
    }

    // MARK: - Buffer synthesis (convenience, mainly for tests)

    /// Fill a fresh `[Float]` with `count` samples of the tone at `frequencyHz`.
    ///
    /// This is the easy, allocation-friendly way to get a chunk of tone for
    /// UNIT TESTS (the real-time player uses the `Generator` below to avoid
    /// allocating during playback). We walk the phase forward sample by sample,
    /// wrapping it past 2π so it never grows large enough to lose Float precision.
    ///
    /// - Parameters:
    ///   - count: how many samples to produce (0 → an empty array, no crash).
    ///   - frequencyHz: the pitch in Hertz (≤ 0 → a silent, all-zero buffer).
    ///   - sampleRate: output samples per second.
    /// - Returns: `count` samples, each within `-1.0 ... 1.0`.
    static func samples(count: Int, frequencyHz: Double, sampleRate: Double) -> [Float] {
        // Defensive: a non-positive length is just "no audio".
        guard count > 0 else { return [] }

        let step = phaseStep(frequencyHz: frequencyHz, sampleRate: sampleRate)
        let twoPi = Float.pi * 2

        var phase: Float = 0
        var out = [Float](repeating: 0, count: count)

        for i in 0..<count {
            out[i] = sample(atPhase: phase)
            phase += step
            // Wrap the angle back into 0..<2π. `sin` would be fine with a huge
            // angle mathematically, but a Float loses precision once it gets
            // large, which would slowly detune a long-held note. Subtracting 2π
            // keeps the phase small and the pitch rock-steady.
            if phase >= twoPi { phase -= twoPi }
        }

        return out
    }

    // MARK: - Real-time phase generator (no per-sample allocation)

    /// A tiny stateful sample source for the real-time render callback in
    /// `ToneGenerator`. It remembers the running `phase` between calls so a long
    /// sustained note stays continuous across the many small buffers the audio
    /// system asks for — and it allocates nothing per sample, which is essential
    /// on the real-time audio thread (allocations there cause glitches).
    ///
    /// It's a `struct` (a value type) holding just two `Float`s, kept inside the
    /// `ToneGenerator` and mutated from its render callback. The DSP is still
    /// pure-ish: given the same starting state and inputs it produces the same
    /// output, so its behavior is covered by the buffer/`sample(atPhase:)` tests.
    struct Generator {
        /// Radians to advance per sample — set from the current target pitch.
        private(set) var phaseStep: Float

        /// The fundamental's current angle in radians, carried between buffers.
        private var phase: Float = 0

        /// Start at a given pitch. `phase` begins at 0 so the very first sample
        /// is `sin(0) = 0` — a clean start from silence (no click).
        ///
        /// `nonisolated` because this is pure value math with no main-actor state:
        /// `ToneGenerator` initializes it in a `nonisolated(unsafe)` stored
        /// property (the real-time render state), and under this project's
        /// main-actor-by-default isolation a plain `init` there would warn
        /// ("call to main actor-isolated initializer in a nonisolated context").
        nonisolated init(frequencyHz: Double, sampleRate: Double) {
            self.phaseStep = ToneOscillator.phaseStep(
                frequencyHz: frequencyHz, sampleRate: sampleRate
            )
        }

        /// Retune to a new pitch WITHOUT resetting the phase. Keeping the phase
        /// continuous means switching strings mid-sustain doesn't pop — the wave
        /// simply changes how fast it advances from wherever it currently is.
        mutating func setFrequency(_ frequencyHz: Double, sampleRate: Double) {
            phaseStep = ToneOscillator.phaseStep(
                frequencyHz: frequencyHz, sampleRate: sampleRate
            )
        }

        /// Produce the next sample and advance the phase. Called once per output
        /// frame from the render callback.
        mutating func nextSample() -> Float {
            let value = ToneOscillator.sample(atPhase: phase)
            phase += phaseStep
            // Same precision-preserving wrap as `samples(...)` above.
            let twoPi = Float.pi * 2
            if phase >= twoPi { phase -= twoPi }
            return value
        }
    }
}
