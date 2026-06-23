//
//  BuiltInTuning.swift
//  GuitarKit
//
//  A tiny starter set of tunings so the tuning-session slice (#05) has real
//  string targets to work with before the full Instruments/Presets system
//  (slice #09) exists.
//
//  ⚠️ PLACEHOLDER: when #09 lands its `Instrument`/`Tuning` model (each
//  instrument owning its tunings and headstock layout), the standard guitar
//  tuning will come from there and this file should be folded into it. It lives
//  apart for now precisely so it's easy to find and delete later.
//

import Foundation

/// A namespace (empty `enum`) for hard-coded tunings expressed as low-to-high
/// open-string notes — the order a guitarist reads strings (6th string first).
enum BuiltInTuning {

    /// Standard six-string guitar tuning, low E to high E (EADGBE).
    ///
    /// These are the open-string notes; the session derives each string's
    /// frequency target through `PitchCalculator` (so reference pitch, capo, and
    /// temperament all apply uniformly). Octaves use scientific pitch notation:
    /// the low E is E2 (~82 Hz), the high E is E4 (~330 Hz).
    static let standardGuitar: [Note] = [
        Note(pitchClass: .e, octave: 2),   // 6th string, low E  (~82.41 Hz)
        Note(pitchClass: .a, octave: 2),   // 5th string, A      (~110.00 Hz)
        Note(pitchClass: .d, octave: 3),   // 4th string, D      (~146.83 Hz)
        Note(pitchClass: .g, octave: 3),   // 3rd string, G      (~196.00 Hz)
        Note(pitchClass: .b, octave: 3),   // 2nd string, B      (~246.94 Hz)
        Note(pitchClass: .e, octave: 4)    // 1st string, high E (~329.63 Hz)
    ]
}
