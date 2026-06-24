//
//  ChromaticZone.swift
//  GuitarKit
//
//  The PURE deviation classifier for CHROMATIC mode.
//
//  In targeted tuning, `TuningSession.zone` decides how flat/sharp you are
//  against a chosen string's target. Chromatic mode has NO chosen string — the
//  detector already names the nearest note for *any* pitch and reports how many
//  cents off it is. So all we need is the *same* flat/sharp/in-tune/perfect
//  classification, but standing alone, without a session to own it.
//
//  WHY A SEPARATE TINY FUNCTION (instead of reusing TuningSession)?
//  `TuningSession` is a stateful machine built around string targets, holding,
//  latching, etc. Spinning one up just to classify a single cents value would be
//  overkill and would drag in concepts (targets, hold timers) that don't exist
//  in chromatic mode. A free function is the smallest thing that does the job —
//  and because it's pure (input → output, no state, no UI, no clock) it's the
//  cheapest, most valuable thing to unit-test. It deliberately mirrors the
//  thresholds in `TuningSession.zone` so both modes agree on what "in tune" means.
//
//  This file has NO SwiftUI import on purpose: it's plain domain logic.
//

import Foundation

// MARK: - Chromatic zone classification

/// Namespace for chromatic-mode helpers. An empty `enum` can't be instantiated,
/// so it reads purely as a container for related `static` functions/values —
/// the same "namespace" trick used by `GKColor` / `GKFont`. Callers write
/// `ChromaticZone.classify(cents:)`.
enum ChromaticZone {

    /// The thresholds that define "in tune" / "perfect" in chromatic mode, in
    /// cents. These intentionally match the PRD's shipping tuning tolerances
    /// (`TuningTolerance.standard`: perfect ≤±1¢, in tune ≤±3¢) so the two modes
    /// feel consistent. They live here as named constants so the boundaries are
    /// obvious and so the tests can reference the exact same numbers.
    static let perfectCents: Double = 1
    static let inTuneCents: Double = 3

    /// Classify a signed cent offset into a `TuningZone`.
    ///
    /// We reuse the SAME `TuningZone` enum the tuning domain already defines
    /// (`flat` / `sharp` / `inTune` / `perfect`) rather than inventing a parallel
    /// type — one vocabulary for "how in tune am I?" across the whole app, which
    /// also means `CentsMeterView` (which takes a `TuningZone?`) just works here.
    ///
    /// - Parameter cents: signed deviation from the nearest note. Positive =
    ///   sharp (too high), negative = flat (too low). `nil` means "no live
    ///   reading" and maps to `nil` (no zone) so callers can render an idle state.
    /// - Returns: the matching zone, or `nil` when `cents` is `nil`.
    ///
    /// CLASSIFICATION ORDER MATTERS: we test the *tightest* window first.
    /// `abs(cents)` collapses direction so one comparison covers both signs:
    ///   • within ±1¢  → `.perfect`
    ///   • within ±3¢  → `.inTune`
    ///   • otherwise   → direction decides: negative → `.flat`, else `.sharp`.
    /// Because the perfect/in-tune checks already caught everything ≤3¢, anything
    /// reaching the final line is genuinely out of tune, so the sign is a safe
    /// tie-break. Exactly 0¢ is caught by the first `.perfect` branch.
    static func classify(cents: Double?) -> TuningZone? {
        // No reading → no zone. Using `guard let` to unwrap keeps the happy path
        // un-nested below.
        guard let cents else { return nil }

        let magnitude = abs(cents)                 // distance from the note, ignoring direction
        if magnitude <= perfectCents { return .perfect }
        if magnitude <= inTuneCents { return .inTune }
        // Out of tune: which way? Negative cents = flat (below), positive = sharp.
        return cents < 0 ? .flat : .sharp
    }
}
