//
//  FretboardScale.swift
//  GuitarKit — Fretboard domain
//
//  Maps a `Scale` onto a `Fretboard`: which board positions are IN the scale,
//  which are the ROOT (for emphasis), each position's scale DEGREE (for the
//  degree-labels mode), and an ordered note sequence for play ascending/
//  descending. Pure (no UI) so the membership logic is unit-tested directly.
//
//  This is set membership on PITCH CLASS: a fret is "in the scale" when the note
//  it sounds (ignoring octave) is one of the scale's pitch classes. Because the
//  fretboard is already tuning- + capo-aware, the highlighting is automatically
//  correct for any tuning, any capo — the PRD's "everything is tuning-aware".
//

import Foundation

/// A scale projected onto a fretboard.
public struct FretboardScale: Sendable {

    public let fretboard: Fretboard
    public let scale: Scale

    public init(fretboard: Fretboard, scale: Scale) {
        self.fretboard = fretboard
        self.scale = scale
    }

    /// Whether the note at `(string, fret)` belongs to the scale.
    public func isInScale(string: Int, fret: Int) -> Bool {
        guard let note = fretboard.note(string: string, fret: fret) else { return false }
        return scale.pitchClassSet.contains(note.pitchClass)
    }

    /// Whether `(string, fret)` is a ROOT note of the scale (for emphasis).
    public func isRoot(string: Int, fret: Int) -> Bool {
        guard let note = fretboard.note(string: string, fret: fret) else { return false }
        return note.pitchClass == scale.root
    }

    /// The 1-based scale degree of `(string, fret)` (1 = root, 2 = second…), or
    /// `nil` if the position isn't in the scale. Drives the "degrees" label mode.
    public func degree(string: Int, fret: Int) -> Int? {
        guard let note = fretboard.note(string: string, fret: fret) else { return nil }
        // `scale.notes` is ordered from the root, so the index + 1 is the degree.
        return scale.notes.firstIndex(of: note.pitchClass).map { $0 + 1 }
    }

    /// All distinct in-scale notes across the board, ascending by pitch — the
    /// sequence "play ascending" sounds. Deduplicated by MIDI number so a pitch
    /// reachable on several strings plays once.
    public func ascendingNotes() -> [Note] {
        var midis: Set<Int> = []
        for string in fretboard.openStrings.indices {
            for fret in 0...fretboard.fretCount {
                guard let note = fretboard.note(string: string, fret: fret),
                      scale.pitchClassSet.contains(note.pitchClass) else { continue }
                midis.insert(note.midiNumber)
            }
        }
        return midis.sorted().map(Note.from(midiNumber:))
    }

    /// The same notes, highest → lowest, for "play descending".
    public func descendingNotes() -> [Note] {
        ascendingNotes().reversed()
    }
}
