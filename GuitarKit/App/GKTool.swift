//
//  GKTool.swift
//  GuitarKit
//
//  The five tools the app is made of, modeled as one enum.
//
//  WHY AN ENUM?
//  The set of tools is fixed and known at compile time (Tuner, Metronome,
//  Circle of Fifths, Chords, Scales). An `enum` is Swift's perfect fit for
//  "one of a fixed set of choices": the compiler can guarantee we've handled
//  every case (exhaustive `switch`), and we can't ever construct an invalid
//  tool. This single source of truth drives both the navigation and the
//  placeholder screens.
//

import SwiftUI

/// One of GuitarKit's five tools.
///
/// Conformances explained:
/// - `String` raw value: gives each case a stable text identity, handy for
///   debugging/persistence later.
/// - `CaseIterable`: auto-synthesizes `GKTool.allCases`, an array of every
///   case in declaration order. The rotary nav iterates this so it never goes
///   out of sync with the enum.
/// - `Identifiable`: lets SwiftUI's `ForEach` tell cases apart (it needs a
///   stable `id`). We satisfy it with the raw value below.
enum GKTool: String, CaseIterable, Identifiable {
    case tuner
    case metronome
    case circleOfFifths
    case chords
    case scales

    /// `Identifiable` requirement. The raw `String` is already unique per
    /// case, so it's a natural id.
    var id: String { rawValue }

    /// Human-facing name shown under each nav tab and as each screen's title.
    var title: String {
        switch self {
        case .tuner:          return "Tuner"
        case .metronome:      return "Metronome"
        case .circleOfFifths: return "Circle of Fifths"
        case .chords:         return "Chords"
        case .scales:         return "Scales"
        }
    }

    /// Shorter label for the cramped rotary-nav arc, where the full
    /// "Circle of Fifths" wouldn't fit.
    var shortTitle: String {
        switch self {
        case .circleOfFifths: return "Circle"
        default:              return title
        }
    }

    /// An SF Symbol that represents each tool. SF Symbols are Apple's built-in
    /// icon set; referencing one by name with `Image(systemName:)` gives us a
    /// crisp, Dynamic-Type-aware glyph for free.
    var systemImage: String {
        switch self {
        case .tuner:          return "tuningfork"
        case .metronome:      return "metronome"
        case .circleOfFifths: return "circle.hexagonpath"
        case .chords:         return "guitars"
        case .scales:         return "music.note.list"
        }
    }
}
