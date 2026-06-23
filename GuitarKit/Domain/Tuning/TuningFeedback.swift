//
//  TuningFeedback.swift
//  GuitarKit
//
//  The PURE decision of "which feedback event (if any) should fire as the tuning
//  zone changes?" — pulled out of the haptics/UI so it can be unit-tested.
//
//  WHY SEPARATE THIS FROM THE HAPTICS CODE?
//  Actually playing a haptic needs UIKit and a real device, which we can't (and
//  shouldn't) unit-test. But the *rule* — "fire the perfect tick the moment you
//  first reach ±1¢, the in-tune tick the moment you first reach ±3¢, and don't
//  re-fire while you stay there or as you drift back out" — is just logic. We
//  isolate that logic here as a pure function over the previous and current
//  `TuningZone`, test it exhaustively, and let the model translate the result
//  into an actual buzz.
//

import Foundation

/// A discrete feedback moment worth a distinct haptic. The PRD asks for *two
/// distinct* ticks: one when a string reaches in-tune (±3¢) and a crisper one
/// when it reaches perfect (±1¢).
public enum TuningFeedbackEvent: Equatable, Sendable {
    case enteredInTune
    case enteredPerfect
}

/// Decide whether moving from `previous` to `current` zone is a moment that
/// should fire a feedback tick.
///
/// THE RULES (so a tick fires once, on *arrival*, not continuously):
///   • Reaching `.perfect` from anything that wasn't already perfect → a
///     perfect tick. (Even straight from flat/sharp or from a cold start.)
///   • Reaching `.inTune` from outside the in-tune band (flat/sharp/nil) → an
///     in-tune tick. But NOT when easing back from `.perfect` into `.inTune` —
///     that's drifting away from the goal, not arriving, so it stays silent.
///   • Staying put, or moving to flat/sharp, fires nothing.
///
/// - Parameters:
///   - previous: the zone on the prior reading (`nil` if there was none).
///   - current: the zone now (`nil` if the signal dropped out).
/// - Returns: the event to fire, or `nil` for "no tick".
public func tuningFeedbackEvent(
    from previous: TuningZone?,
    to current: TuningZone?
) -> TuningFeedbackEvent? {
    switch current {
    case .perfect:
        // Fire unless we were already perfect (avoid repeating while held).
        return previous == .perfect ? nil : .enteredPerfect

    case .inTune:
        // Fire only when arriving from OUTSIDE the in-tune band. Coming down
        // from perfect (perfect → inTune) is drifting out, so stay silent; and
        // staying in-tune repeats nothing.
        switch previous {
        case .inTune, .perfect: return nil
        default:                return .enteredInTune   // flat / sharp / nil
        }

    case .flat, .sharp, nil:
        // Out of tune, or no reading — no arrival tick.
        return nil
    }
}
