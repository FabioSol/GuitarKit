//
//  TunerDevConfig.swift
//  GuitarKit
//
//  DEVELOPER-ONLY tuning knobs for A/B-ing the tuner's feel. This whole file is
//  wrapped in `#if DEBUG`, so it (and everything that reads it) is COMPILED OUT
//  of release builds — shipping users never get these controls, per slice #07's
//  acceptance criteria ("dev-only controls are compiled out of release builds").
//
//  It holds the in-tune threshold (how forgiving "in tune" is) and the pitch
//  tracker's knobs (algorithm, gates, smoothing, band-pass on/off). The
//  tracker knobs START from `PitchTrackerConfig`'s defaults, so the Lab and
//  the shipping tuner can never silently disagree.
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
    /// laggy; near 1 = snappy but jittery.
    var smoothing = Double(PitchTrackerConfig().smoothing)

    /// The MPM clarity gate (0…1). Lower catches more (decaying/quiet guitar);
    /// higher rejects more noise.
    var clarityThreshold = Double(PitchTrackerConfig().clarityThreshold)

    /// The input level gate in dBFS (measured on the FILTERED, in-band signal).
    /// Lower admits quieter / decaying notes; higher ignores more background.
    var levelGateDB = Double(PitchTrackerConfig().levelGateDB)

    /// Which detection algorithm runs (MPM / YIN / Ensemble). The panel lets us
    /// A/B them on a real instrument.
    var algorithm = PitchTrackerConfig().algorithm

    /// Band-pass preprocessing (the low-string fix) on/off, for A/B-ing its
    /// effect on a real instrument. The corners themselves are NOT tunable —
    /// they're derived from the selected tuning (`DetectionBand`), and a manual
    /// override here would just fight that derivation.
    var preprocessEnabled = PitchTrackerConfig().preprocessingEnabled

    /// Which pipeline turns detections into readings in targeted mode:
    /// gated (per-frame gates) or probabilistic (a belief over which string
    /// is ringing). Chromatic mode always uses gated.
    var engine = PitchTrackerConfig().engine

    /// The harmonic check's gate in targeted mode (0 = off). Lower lets more
    /// through (soft/messy strings, but also voices); higher blocks more.
    var harmonicGate = Double(PitchTrackerConfig.targetedModeHarmonicGate)
}
#endif
