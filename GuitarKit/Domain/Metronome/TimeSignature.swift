//
//  TimeSignature.swift
//  GuitarKit — Metronome configuration
//
//  How many beats make up one bar (and what note value gets the beat). This is
//  the musical "shape" of the metronome: a 3/4 waltz cycles through 3 beats per
//  bar, a 4/4 rock groove through 4, a 7/8 odd-meter through 7. The beat-ring in
//  the UI redraws to `beatsPerBar`, and the engine schedules accents per beat,
//  so this little value drives a lot of behavior downstream.
//
//  WHY A PURE STRUCT (Foundation only)?
//  Same philosophy as `MetronomeSequencer`/`TapTempo`: keep the *musical
//  decisions* in a tiny, deterministic value type with no audio or UI baked in.
//  That makes it trivially unit-testable (presets are correct, the custom
//  initializer clamps), and it can be used safely off the main actor.
//
//  A NOTE ON "BEATS" VS "NOTE VALUE":
//  A time signature is written as two numbers, e.g. 6/8. The TOP number is how
//  many beats are in a bar; the BOTTOM is which note value counts as one beat
//  (4 = quarter note, 8 = eighth note). For THIS metronome, what actually
//  matters for clicking and ring-drawing is the top number (`beatsPerBar`) — we
//  click once per beat. We still carry the bottom number (`noteValue`) so the UI
//  can label the signature correctly ("6/8"), but the timing math only ever uses
//  `beatsPerBar`. (We're deliberately NOT subdividing 6/8 into two dotted-quarter
//  pulses here — that musical nuance is out of scope; 6/8 simply means six clicks
//  per bar. The subdivision feature handles in-between ticks separately.)
//

import Foundation

/// One bar's worth of beats: how many clicks per bar (`beatsPerBar`) plus the
/// note value that gets the beat (`noteValue`, for display only).
///
/// `Equatable`/`Hashable` so SwiftUI pickers and the view model can compare and
/// store signatures cheaply. `Sendable` because it's a plain value with no
/// reference types — safe to hand between actors.
struct TimeSignature: Equatable, Hashable, Sendable {

    // MARK: - Clamp bounds

    /// The smallest and largest beat counts we allow. One beat is the minimum
    /// that still "means" anything; 16 is a generous ceiling that keeps the
    /// beat-ring readable and the dots from crowding together. Custom counts are
    /// clamped into this range so no input path can produce a 0- or 99-beat bar.
    static let minBeats = 1
    static let maxBeats = 16

    // MARK: - Stored properties

    /// How many beats (clicks) make up one bar. This is the value the engine and
    /// the beat-ring both read. Always within `minBeats...maxBeats`.
    let beatsPerBar: Int

    /// Which note value gets one beat (4 = quarter, 8 = eighth). Display-only —
    /// the timing math never uses it; it's here so the UI can render "6/8".
    let noteValue: Int

    // MARK: - Initializer (clamping)

    /// Build a time signature, clamping `beatsPerBar` into the allowed range so
    /// callers can pass any integer (e.g. straight from a stepper) without
    /// risking an invalid bar.
    ///
    /// `nonisolated` is unnecessary here because the struct touches no global
    /// or main-actor state — it's pure value math — but we keep the body free of
    /// any actor-bound work so it stays usable from tests on any thread.
    ///
    /// - Parameters:
    ///   - beatsPerBar: desired beats per bar; clamped to `minBeats...maxBeats`.
    ///   - noteValue: the note that gets the beat (defaults to 4, a quarter
    ///     note — the most common). Not validated beyond being stored as-is.
    init(beatsPerBar: Int, noteValue: Int = 4) {
        // `min(max(...))` is the standard two-sided clamp: floor first, then
        // ceiling. A 0 becomes 1; a 99 becomes 16.
        self.beatsPerBar = min(max(beatsPerBar, Self.minBeats), Self.maxBeats)
        self.noteValue = noteValue
    }

    // MARK: - Display

    /// The conventional "top/bottom" label, e.g. "4/4" or "6/8". Used by the
    /// time-signature picker so each option reads the way musicians write it.
    var label: String { "\(beatsPerBar)/\(noteValue)" }

    // MARK: - Common presets
    //
    // The signatures most players reach for, offered as ready-made values so the
    // UI can show a row of familiar choices. Each is just a call to the clamping
    // initializer with well-known numbers.

    /// 2/4 — a march / simple duple.
    static let twoFour = TimeSignature(beatsPerBar: 2, noteValue: 4)
    /// 3/4 — a waltz.
    static let threeFour = TimeSignature(beatsPerBar: 3, noteValue: 4)
    /// 4/4 — "common time," the default for most pop/rock.
    static let fourFour = TimeSignature(beatsPerBar: 4, noteValue: 4)
    /// 5/4 — an odd meter (think "Take Five").
    static let fiveFour = TimeSignature(beatsPerBar: 5, noteValue: 4)
    /// 6/8 — six eighth-note clicks per bar (compound feel).
    static let sixEight = TimeSignature(beatsPerBar: 6, noteValue: 8)
    /// 7/8 — a brisk odd meter.
    static let sevenEight = TimeSignature(beatsPerBar: 7, noteValue: 8)

    /// The presets in the order the picker should show them. Handy for building
    /// a menu with `ForEach` without re-listing them in the view.
    static let presets: [TimeSignature] = [
        .twoFour, .threeFour, .fourFour, .fiveFour, .sixEight, .sevenEight
    ]
}
