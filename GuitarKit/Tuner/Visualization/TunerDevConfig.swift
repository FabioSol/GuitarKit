//
//  TunerDevConfig.swift
//  GuitarKit
//
//  DEVELOPER-ONLY tuning knobs for A/B-ing the tuner's feel. This whole file is
//  wrapped in `#if DEBUG`, so it (and everything that reads it) is COMPILED OUT
//  of release builds — shipping users never get these controls, per slice #07's
//  acceptance criteria ("dev-only controls are compiled out of release builds").
//
//  It holds three live-tweakable things:
//    • which visualization the hero wears (linear vs radial)
//    • the in-tune threshold, in cents (how forgiving "in tune" is)
//    • the smoothing factor fed to the pitch detector (jittery ↔ sluggish)
//
//  These exist so we can find the right defaults by FEEL on a device, then bake
//  the winners into the real Settings / domain defaults.
//

#if DEBUG
import Observation

/// Live A/B knobs for the tuner. `@Observable` so the hero re-renders when the
/// visualization changes, and `@MainActor` because it's read/written from the UI.
@MainActor
@Observable
final class TunerDevConfig {

    /// The "in tune" half-window, in cents. Lower = stricter (harder to satisfy),
    /// higher = more forgiving. Mirrors `TuningTolerance.inTuneCents`; the tuner
    /// reapplies it to the session whenever it changes. Default matches the
    /// app's "standard" sensitivity (±5¢).
    var inTuneThresholdCents: Double = 5

    /// The pitch detector's EMA smoothing factor (0…1). Near 0 = very smooth but
    /// laggy; near 1 = snappy but jittery. Default matches `PitchSmoother`'s 0.25.
    var smoothing: Double = 0.25

    /// The MPM clarity gate (0…1). Lower catches more (decaying/quiet guitar);
    /// higher rejects more noise. Default matches the detector.
    var clarityThreshold: Double = 0.6

    /// The input level gate in dBFS. Lower admits quieter / decaying notes;
    /// higher ignores more background. Default matches the detector.
    var levelGateDB: Double = -52

    /// Which detection algorithm runs (MPM / YIN / Ensemble). Default matches the
    /// detector; the panel lets us A/B them on a real instrument.
    var algorithm: PitchAlgorithm = .ensemble
}
#endif
