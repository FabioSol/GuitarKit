//
//  ToolLabelMode.swift
//  GuitarKit — shared tool support
//
//  How the Chords and Scales tools label the dots on their fretboard diagrams. The
//  two tools offer the identical choice — note names vs. scale/chord degrees — so
//  the toggle lives here once. Each view model exposes it as a nested
//  `LabelMode` typealias so existing call sites (`ScalesViewModel.LabelMode`,
//  `ChordsViewModel.LabelMode`) keep reading naturally.
//

/// Dot-label choice shared by the Chords and Scales tools.
///   • `.noteNames` → "C", "E", "G" on the dots.
///   • `.degrees`   → the scale/chord degree ("1", "3", "5", "♭7"…).
enum ToolLabelMode: CaseIterable, Hashable {
    case noteNames
    case degrees
}
