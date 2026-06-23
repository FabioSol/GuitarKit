//
//  ReferencePitch.swift
//  GuitarKit
//
//  The calibration anchor for the whole tuning system: the frequency assigned
//  to A4 (MIDI 69). Concert pitch is A=440 Hz, but ensembles and old recordings
//  use other values (Baroque ~415, "brighter" orchestras ~442/443). The PRD
//  exposes a calibration range of A=415...466.
//
//  Pure value logic — no UI, no audio.
//

import Foundation

/// The reference frequency for A4, with the calibration range enforced.
///
/// WHY WRAP A PLAIN `Double`?
/// We *could* pass `referenceA: Double` everywhere, but then nothing stops a
/// bug from setting it to 0 or 9000 Hz. Wrapping it in a small type lets us
/// guarantee the value is always inside the musically-sensible 415...466 band
/// (PRD story 23). This is the "make illegal states unrepresentable" idea: once
/// you hold a `ReferencePitch`, you know it's valid.
///
/// `Equatable`/`Hashable` for comparison & persistence; `Sendable` for safety.
public struct ReferencePitch: Equatable, Hashable, Sendable {
    /// The lowest and highest A4 frequencies the app allows, per the PRD.
    /// `static let` constants live on the type itself, so callers can read
    /// `ReferencePitch.minHz` without making an instance.
    public static let minHz: Double = 415
    public static let maxHz: Double = 466

    /// Concert pitch — the sensible default the app boots with.
    public static let standard = ReferencePitch(hertz: 440)

    /// The validated A4 frequency in Hertz. `private(set)` would also work, but
    /// since the type is immutable we use a plain `let`.
    public let hertz: Double

    /// Create a reference pitch, *clamping* the input into the legal range.
    ///
    /// WHY CLAMP INSTEAD OF FAILING?
    /// A calibration slider/stepper in the UI can only ever feed values at or
    /// near the edges; clamping gives a friendly, non-crashing result (a value
    /// just past the end simply sticks at the end). If a caller needs to *detect*
    /// out-of-range input, they can compare against `minHz`/`maxHz` first.
    public init(hertz: Double) {
        // `min`/`max` compose into a clamp: first cap the top, then floor the
        // bottom. e.g. clamp(500) -> min(500,466)=466 -> max(466,415)=466.
        self.hertz = Swift.max(Self.minHz, Swift.min(Self.maxHz, hertz))
    }
}
