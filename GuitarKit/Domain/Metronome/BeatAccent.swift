//
//  BeatAccent.swift
//  GuitarKit — Metronome configuration
//
//  The role of an individual beat in the bar. Each dot in the beat-ring carries
//  one of these, and tapping the dot cycles through them:
//
//      accent  → the loud, emphasized click (typically the downbeat "1")
//      normal  → a regular click
//      muted   → silent: the beat still "happens" (the ring still moves, the
//                timing slot is still reserved) but NO click is scheduled
//
//  WHY "muted" MATTERS FOR TIMING:
//  Because the engine schedules every tick at an absolute, anchored sample
//  offset, a muted beat is handled by simply NOT scheduling a buffer for that
//  slot while STILL advancing the tick index. The silence sits in exactly the
//  right place and the following beats stay perfectly on time — muting never
//  shifts anything. (It's also the basis of "silent practice": mute everything,
//  turn on the per-beat haptic, and you feel the pulse with no sound.)
//
//  WHY A PURE ENUM:
//  Like the other config types, this is a tiny testable value. The one behavior
//  worth testing is the CYCLE order (`next`), which the tap-a-dot gesture relies
//  on. `CaseIterable` lets callers iterate all three if needed.
//

import Foundation

/// One beat's emphasis. Tapping a beat-ring dot advances it via `next`.
///
/// `CaseIterable`/`Equatable`/`Hashable`/`Sendable` for the same reasons as the
/// other config enums (listing, comparing, storing, crossing actors).
enum BeatAccent: CaseIterable, Equatable, Hashable, Sendable {
    /// Emphasized — the loud click, usually beat 1.
    case accent
    /// A regular click.
    case normal
    /// Silent: the slot is reserved but no click sounds.
    case muted

    /// The next state in the tap cycle: accent → normal → muted → accent → …
    ///
    /// We spell the cycle out explicitly (rather than indexing `allCases`) so the
    /// order is obvious at a glance and can't be accidentally changed by
    /// reordering the cases. This is what `cycleAccent(at:)` calls when the user
    /// taps a dot.
    var next: BeatAccent {
        switch self {
        case .accent: return .normal
        case .normal: return .muted
        case .muted:  return .accent
        }
    }

    /// A short word describing the state, for VoiceOver labels and any text hint
    /// in the UI. Keeps the spoken description in one place.
    var displayHint: String {
        switch self {
        case .accent: return "Accent"
        case .normal: return "Normal"
        case .muted:  return "Muted"
        }
    }
}
