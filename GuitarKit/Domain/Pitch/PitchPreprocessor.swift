//
//  PitchPreprocessor.swift
//  GuitarKit
//
//  A PURE band-pass preprocessing stage that runs BEFORE pitch detection, to
//  make the low strings detectable.
//
//  THE PROBLEM IT SOLVES:
//  On a plucked low string the FUNDAMENTAL is often quieter than its 2nd/3rd
//  harmonics (the body + mic emphasise the mids). Autocorrelation detectors then
//  lock onto a harmonic (octave error) or the fundamental's periodicity is too
//  weak to pass the clarity gate. Meanwhile the low region is full of mains hum
//  (50/60 Hz), rumble and handling noise. So:
//
//    • a HIGH-PASS (~65 Hz) removes hum / rumble / DC — below a guitar's low E
//      (82 Hz), so the note itself is untouched.
//    • a LOW-PASS (~1 kHz) tames the loud high harmonics + hiss, so the
//      FUNDAMENTAL'S periodicity dominates what MPM/YIN see.
//
//  Filtering changes amplitude/phase but NOT the fundamental period, so tuning
//  accuracy is preserved — the detector still reports the right pitch, just more
//  reliably on the low strings.
//
//  It's STATEFUL (the biquads carry their delay memory between buffers) so there
//  is no per-buffer transient; the detector resets it when the signal drops out.
//

import Foundation

// MARK: - Biquad

/// A second-order IIR filter ("biquad"), the standard building block for clean
/// low-/high-pass filters. Uses the RBJ "cookbook" coefficients and the
/// Transposed Direct Form II structure (numerically friendly, two state words).
struct Biquad: Equatable {

    // Feed-forward / feed-back coefficients (already normalised by a0).
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0
    private var a1: Float = 0, a2: Float = 0
    // Delay state.
    private var z1: Float = 0, z2: Float = 0

    /// A low-pass filter at `cutoffHz`. `q` = 0.707 is Butterworth (maximally flat).
    static func lowPass(cutoffHz: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
        var bq = Biquad()
        bq.setLowPass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q)
        return bq
    }

    /// A high-pass filter at `cutoffHz`.
    static func highPass(cutoffHz: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
        var bq = Biquad()
        bq.setHighPass(cutoffHz: cutoffHz, sampleRate: sampleRate, q: q)
        return bq
    }

    /// RBJ cookbook low-pass coefficients. `w0` is the cutoff as an angle per
    /// sample; `alpha` sets the bandwidth from `q`.
    mutating func setLowPass(cutoffHz: Double, sampleRate: Double, q: Double = 0.707) {
        let w0 = 2 * Double.pi * cutoffHz / sampleRate
        let cosw0 = cos(w0), sinw0 = sin(w0)
        let alpha = sinw0 / (2 * q)
        let a0 = 1 + alpha
        b0 = Float((1 - cosw0) / 2 / a0)
        b1 = Float((1 - cosw0) / a0)
        b2 = b0
        a1 = Float(-2 * cosw0 / a0)
        a2 = Float((1 - alpha) / a0)
    }

    /// RBJ cookbook high-pass coefficients.
    mutating func setHighPass(cutoffHz: Double, sampleRate: Double, q: Double = 0.707) {
        let w0 = 2 * Double.pi * cutoffHz / sampleRate
        let cosw0 = cos(w0), sinw0 = sin(w0)
        let alpha = sinw0 / (2 * q)
        let a0 = 1 + alpha
        b0 = Float((1 + cosw0) / 2 / a0)
        b1 = Float(-(1 + cosw0) / a0)
        b2 = b0
        a1 = Float(-2 * cosw0 / a0)
        a2 = Float((1 - alpha) / a0)
    }

    /// Filter one sample, advancing the delay state.
    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    /// Clear the delay memory (call when the signal restarts).
    mutating func reset() { z1 = 0; z2 = 0 }
}

// MARK: - Preprocessor

/// The band-pass stage applied to each buffer before detection.
struct PitchPreprocessor {

    /// Whether filtering is applied at all (off = pass-through).
    var isEnabled: Bool
    /// High-pass corner — removes hum/rumble below this.
    private(set) var highPassHz: Double
    /// Low-pass corner — tames harmonics/hiss above this.
    private(set) var lowPassHz: Double

    private var hp = Biquad()
    private var lp = Biquad()
    /// The sample rate the biquads are currently tuned for (0 = not yet built).
    private var configuredRate: Double = 0

    init(highPassHz: Double = 65, lowPassHz: Double = 1000, enabled: Bool = true) {
        self.highPassHz = highPassHz
        self.lowPassHz = lowPassHz
        self.isEnabled = enabled
    }

    /// Band-pass one buffer. Rebuilds the filters if the sample rate changed since
    /// last time (the rate isn't known until audio actually flows).
    mutating func process(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard isEnabled, sampleRate > 0 else { return samples }
        if sampleRate != configuredRate { configure(sampleRate: sampleRate) }
        // High-pass then low-pass, per sample, carrying state across the buffer.
        return samples.map { lp.process(hp.process($0)) }
    }

    /// (Re)build the biquads for `sampleRate` and clear their state.
    mutating func configure(sampleRate: Double) {
        hp.setHighPass(cutoffHz: min(highPassHz, sampleRate / 2 - 1), sampleRate: sampleRate)
        lp.setLowPass(cutoffHz: min(lowPassHz, sampleRate / 2 - 1), sampleRate: sampleRate)
        configuredRate = sampleRate
        hp.reset(); lp.reset()
    }

    /// Clear filter memory — call when the input drops out so a new note starts
    /// from a clean filter state.
    mutating func reset() { hp.reset(); lp.reset() }

    /// Live-tune the corners (Tuner Lab). Rebuilds if we're already configured.
    mutating func setCutoffs(highPassHz: Double, lowPassHz: Double) {
        self.highPassHz = highPassHz
        self.lowPassHz = lowPassHz
        if configuredRate > 0 { configure(sampleRate: configuredRate) }
    }
}
