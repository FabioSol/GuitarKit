//
//  MetronomeHaptics.swift
//  GuitarKit — Metronome
//
//  A tiny wrapper around UIKit's impact haptics for the metronome's per-beat
//  "tick you can feel." When haptics are enabled, the engine fires one of these
//  on every BEAT (not on the in-between subdivisions — that would be a buzzing
//  blur). Combined with muting the sound, this enables SILENT PRACTICE: you keep
//  time by feel (and by watching the beat-ring) with no audible click.
//
//  WHY A SEPARATE TYPE FROM `TuningHaptics`?
//  The tuner's haptics are a different vocabulary (in-tune / perfect / latched /
//  done) and we were told not to touch it. The metronome only needs ONE buzz —
//  the beat — so this is deliberately minimal. We keep the same house pattern,
//  though: a `@MainActor` type holding a pre-`prepare()`-d generator so the first
//  tap isn't delayed by the Taptic Engine spinning up.
//
//  WHY ACCENT VS. NORMAL GET DIFFERENT STRENGTHS:
//  So the downbeat *feels* like the downbeat. The accented beat gets a firmer
//  `rigid` thump; ordinary beats get a `light` tap. That mirrors the audible
//  accent hierarchy in the fingertips.
//
//  DEVICE-ONLY:
//  Haptics do nothing in the simulator or in tests — that's fine. There's no
//  pure logic to test here (the *decision* of whether/when to buzz lives in the
//  engine and view model); this type only performs the buzz.
//

import UIKit

/// Performs the metronome's per-beat haptic. `@MainActor` because UIKit's
/// feedback generators must be used from the main thread.
@MainActor
final class MetronomeHaptics {

    // Pre-allocated generators kept alive (and `prepare()`-d) so the Taptic
    // Engine is warm for low-latency taps. `rigid` for the accent (a crisper,
    // firmer thump), `light` for ordinary beats (a softer tap) — so the downbeat
    // feels distinct from the rest.
    private let accentImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let normalImpact = UIImpactFeedbackGenerator(style: .light)

    init() {}

    /// Warm up the generators. Call before starting so the first beat's buzz
    /// isn't delayed by the engine spinning up.
    func prepare() {
        accentImpact.prepare()
        normalImpact.prepare()
    }

    /// Buzz for a beat. `accented` picks the firmer thump for accented beats.
    /// Re-`prepare()`s afterward (cheap) to keep the next beat's latency low.
    ///
    /// Note we intentionally still buzz for a *muted* beat — muting silences the
    /// SOUND, not the feel; that's the whole point of silent practice. The engine
    /// decides accent-vs-normal from the beat's `BeatAccent` (treating `.muted`
    /// as a normal-strength tap so you still feel every pulse).
    func beat(accented: Bool) {
        if accented {
            accentImpact.impactOccurred(intensity: 1.0)
            accentImpact.prepare()
        } else {
            normalImpact.impactOccurred()
            normalImpact.prepare()
        }
    }
}
