//
//  TuningHaptics.swift
//  GuitarKit
//
//  The thin wrapper around UIKit's haptic feedback generators for the tuner.
//  Four distinct sensations map to the four tuning milestones (PRD stories 12, 8):
//
//      reach in-tune (±3¢)   → a LIGHT tick
//      reach perfect (±1¢)   → a RIGID, crisper tick  (distinct from in-tune)
//      a string LATCHES      → a SUCCESS notification
//      ALL strings done      → a heavier success flourish
//
//  WHY A SMALL CLASS BEHIND A PROTOCOL?
//  Haptics only fire on a real device — the simulator and unit tests can't feel
//  them. Hiding the generators behind `TuningHapticsProviding` means the model
//  depends on an interface, so a no-op fake can stand in for previews/tests
//  while the real one runs on device. (The *decision* of when to buzz is the
//  pure, tested `tuningFeedbackEvent(...)`; this type only performs the buzz.)
//

import UIKit

/// What the model calls to produce tuning haptics.
@MainActor
protocol TuningHapticsProviding: AnyObject {
    /// Warm up the generators so the first tap isn't delayed.
    func prepare()
    /// A string just reached the in-tune band (±3¢).
    func inTune()
    /// A string just reached the perfect band (±1¢) — a distinct, crisper tick.
    func perfect()
    /// A string just latched (hold-to-confirm completed).
    func stringLatched()
    /// Every string is now in tune.
    func sessionCompleted()
}

/// The real, device-backed implementation.
@MainActor
final class TuningHaptics: TuningHapticsProviding {

    // Pre-allocated generators. Keeping instances around (and `prepare()`-ing
    // them) lets the Taptic Engine spin up ahead of time for low-latency taps.
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notifier = UINotificationFeedbackGenerator()

    func prepare() {
        lightImpact.prepare()
        rigidImpact.prepare()
        notifier.prepare()
    }

    func inTune() {
        // A soft tap — "you're basically there."
        lightImpact.impactOccurred()
        // Re-prepare for the next one (cheap, keeps latency low).
        lightImpact.prepare()
    }

    func perfect() {
        // A crisper, more emphatic tap — distinctly different from `inTune`.
        rigidImpact.impactOccurred(intensity: 1.0)
        rigidImpact.prepare()
    }

    func stringLatched() {
        // The system "success" notification pattern — a satisfying confirmation.
        notifier.notificationOccurred(.success)
        notifier.prepare()
    }

    func sessionCompleted() {
        // A restrained two-beat flourish: success + one heavier thump. Not gaudy,
        // just a clear "all done."
        notifier.notificationOccurred(.success)
        heavyImpact.impactOccurred()
    }
}
