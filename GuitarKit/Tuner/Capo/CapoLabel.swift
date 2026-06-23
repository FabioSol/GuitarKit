//
//  CapoLabel.swift
//  GuitarKit
//
//  The PURE text layer for the capo chip: it turns a `Capo` value into the
//  little strings the UI shows (the "+2" badge) and the strings VoiceOver
//  speaks ("Capo on fret 2"). Nothing here imports SwiftUI or UIKit — it's all
//  plain value-in / string-out logic, which is exactly what makes it cheap to
//  unit-test. The view (`CapoControlView`) calls into these helpers so the
//  view stays focused on layout and gestures, not on phrasing.
//
//  WHY SPLIT THE WORDS OUT OF THE VIEW?
//  Two reasons. First, testability: we can assert "+12" appears at fret 12 and
//  nothing appears at fret 0 without ever building a SwiftUI view. Second,
//  single source of truth: the visible badge and the spoken label are derived
//  from the SAME `Capo`, so they can never drift apart.
//

import Foundation

/// A namespace (empty `enum`, the same pattern as `GKColor`/`GKFont`) that
/// groups the capo's display-string helpers. We never make an instance of it;
/// we just call `CapoLabel.badge(for:)` etc.
enum CapoLabel {

    /// The tiny counter shown ON the chip when a capo is engaged — e.g. "+2".
    ///
    /// Returns `nil` when there's no capo (fret 0). Returning an Optional rather
    /// than an empty string lets the view say "if there's a badge, show it;
    /// otherwise show the resting icon" with a clean `if let`. The `+` sign
    /// matches the PRD's "shows a counter (+2)" wording and reads as "raised by
    /// N semitones".
    static func badge(for capo: Capo) -> String? {
        // `isEngaged` is the Capo type's own "fret > 0" check — we reuse it
        // instead of re-testing `fret > 0` here so the "what counts as active"
        // rule lives in exactly one place (the domain type).
        guard capo.isEngaged else { return nil }
        return "+\(capo.fret)"
    }

    /// The phrase VoiceOver reads for the chip — e.g. "No capo" or
    /// "Capo on fret 2".
    ///
    /// Unlike `badge`, this is NEVER nil: an accessibility label should always
    /// describe the current state, including the resting "no capo" state, so a
    /// VoiceOver user always knows where the control stands.
    static func accessibility(for capo: Capo) -> String {
        guard capo.isEngaged else { return "No capo" }
        // Singular/plural is a small courtesy that makes synthesized speech
        // sound natural: "fret 1" reads fine, but we keep the noun "fret"
        // singular here because we're naming a specific fret position, not a
        // count of frets. ("Capo on fret 1", "Capo on fret 2", ...)
        return "Capo on fret \(capo.fret)"
    }
}
