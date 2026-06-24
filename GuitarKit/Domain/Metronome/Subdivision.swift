//
//  Subdivision.swift
//  GuitarKit — Metronome configuration
//
//  How finely each beat is chopped up. The metronome can click not just on the
//  beat, but on the smaller pulses BETWEEN beats — useful for practicing tight
//  rhythms. A subdivision says how many "ticks" fit inside one beat:
//
//      quarter   → 1 tick  per beat (just the beat itself; no in-between clicks)
//      eighth    → 2 ticks per beat (one extra click halfway between beats)
//      triplet   → 3 ticks per beat (two extra clicks, the "1-trip-let" feel)
//      sixteenth → 4 ticks per beat (three extra clicks, "1-e-and-a")
//
//  WHY THIS STAYS DRIFT-FREE:
//  A "tick" is a sub-beat. The engine schedules ticks at absolute sample offsets
//  anchored to tick 0 — exactly like beats are anchored to beat 0 — so chopping
//  a beat into 2/3/4 introduces NO accumulating error. The pure tick math lives
//  in `MetronomeSequencer` (see `samplesPerTick`/`tickOffset`); this enum just
//  names the choices and reports `ticksPerBeat`.
//
//  WHY A PURE ENUM:
//  Same reasoning as `TimeSignature` — a tiny, testable value with no audio or
//  UI. `CaseIterable` so the picker can list every option automatically.
//

import Foundation

/// How many evenly-spaced ticks each beat is divided into.
///
/// `CaseIterable` gives us `Subdivision.allCases` for building the picker;
/// `Equatable`/`Hashable`/`Sendable` so it stores and compares cheaply and
/// crosses actor boundaries safely.
enum Subdivision: CaseIterable, Equatable, Hashable, Sendable {
    /// One tick per beat: clicks land only on the beat (the default; no extra
    /// in-between clicks).
    case quarter
    /// Two ticks per beat: one extra click halfway between each beat.
    case eighth
    /// Three ticks per beat: the swung/even triplet feel ("1-trip-let").
    case triplet
    /// Four ticks per beat: sixteenth notes ("1-e-and-a").
    case sixteenth

    /// How many ticks (sub-beats) fit inside ONE beat. This is the number the
    /// sequencer multiplies the beat spacing down by:
    /// `samplesPerTick = samplesPerBeat / ticksPerBeat`.
    ///
    /// Always ≥ 1, so it's always safe to divide by.
    var ticksPerBeat: Int {
        switch self {
        case .quarter:   return 1
        case .eighth:    return 2
        case .triplet:   return 3
        case .sixteenth: return 4
        }
    }

    /// A short label for the picker. We use the common musical names rather than
    /// the raw tick count so it reads the way a player thinks ("Eighths", not
    /// "2 per beat").
    var label: String {
        switch self {
        case .quarter:   return "Quarter"
        case .eighth:    return "Eighth"
        case .triplet:   return "Triplet"
        case .sixteenth: return "Sixteenth"
        }
    }
}
