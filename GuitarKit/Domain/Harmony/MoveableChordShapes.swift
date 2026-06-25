//
//  MoveableChordShapes.swift
//  GuitarKit — Harmony domain
//
//  A small BANK of moveable (transposable) guitar chord shapes — the familiar
//  "barre" forms a guitarist actually plays — and the logic to place them on the
//  neck for any root by TRANSPOSITION.
//
//  WHY THIS EXISTS:
//  The pure `ChordVoicingGenerator` searches the neck note-by-note and can produce
//  shapes that are technically in-chord but physically UNPLAYABLE (needing five or
//  six independent fingers, or awkward interior mutes). Real chord tools don't
//  generate from scratch — they reuse a handful of KNOWN-GOOD shapes and slide them
//  up the neck. That's exactly what this does: a CAGED-style set of moveable shapes
//  (an "E-shape" barre rooted on the 6th string, an "A-shape" barre rooted on the
//  5th) per chord quality, each placed so its root sits on the chosen root note.
//
//  STANDARD-GUITAR ONLY (by construction):
//  A moveable shape is just a fixed pattern of fret offsets. Those offsets only spell
//  the intended chord because of standard tuning's specific string intervals
//  (E A D G B E). In a different tuning the same offsets would sound a different
//  chord — so these shapes are meaningful ONLY in standard guitar tuning, and the
//  caller (`ChordsViewModel`) gates on that, falling back to the generator otherwise.
//  This mirrors how `StandardChordLibrary` (the curated OPEN shapes) is gated.
//
//  No SwiftUI / AVFoundation — pure value logic, so it's deterministic and testable.
//

import Foundation

// MARK: - A single moveable shape

/// One transposable chord shape, expressed as fret OFFSETS from an "index fret"
/// (the fret the shape is anchored at — typically where the barre sits).
struct MoveableShape: Equatable {

    /// Which chord quality this shape voices (e.g. `.major`). A shape is only ever
    /// placed for chords of its own quality.
    let quality: ChordQuality

    /// A human name for the form ("E-shape", "A-shape") — handy for debugging and a
    /// future barre overlay; not shown to the player yet.
    let name: String

    /// The string (0 = low E) whose note AT THE INDEX FRET is the chord ROOT. This
    /// is the anchor: to place the shape for a target root we find the index fret
    /// where this string sounds that root. Its own offset in `relativeFrets` is 0.
    let rootString: Int

    /// Per string (low → high), the fret offset from the index fret, or `nil` for a
    /// MUTED string. `0` means "at the index fret" (the barre / open position when
    /// the index fret is 0). All offsets are ≥ 0, so the root is the lowest note —
    /// giving a root-in-bass voicing.
    let relativeFrets: [Int?]
}

// MARK: - The bank

/// The library of moveable shapes, and the placement logic that turns them into
/// concrete `ChordVoicing`s for a given root on a given (standard-guitar) board.
enum MoveableChordLibrary {

    /// Place every moveable shape we have for `(root, quality)` on `board`,
    /// transposing each so its root lands on `root`. Returns playable voicings,
    /// ordered low → high up the neck, de-duplicated.
    ///
    /// Intended for STANDARD GUITAR tuning (the shapes assume EADGBE intervals) — the
    /// caller gates on that. Returns an empty array when we have no shape for this
    /// quality, so the caller can fall back to the generator.
    static func voicings(root: PitchClass, quality: ChordQuality, on board: Fretboard) -> [ChordVoicing] {
        let shapes = shapes(for: quality)
        guard !shapes.isEmpty else { return [] }

        var result: [ChordVoicing] = []

        for shape in shapes {
            // Slide the shape up the neck: at each candidate index fret, the shape
            // is valid only where its root string actually sounds the target root.
            for indexFret in 0...board.fretCount {
                guard
                    let rootNote = board.note(string: shape.rootString, fret: indexFret),
                    rootNote.pitchClass == root
                else { continue }

                // Turn the relative offsets into absolute frets, rejecting any that
                // would run off the end of the board.
                guard let frets = absoluteFrets(shape, indexFret: indexFret, board: board) else {
                    continue
                }

                let voicing = ChordVoicing(frets: frets)
                if !result.contains(voicing) {
                    result.append(voicing)
                }
            }
        }

        // Low → high by where the hand sits (open/lowest first), so cycling climbs.
        return result.sorted { ($0.lowestFrettedFret ?? 0) < ($1.lowestFrettedFret ?? 0) }
    }

    /// Convert a shape's relative offsets to absolute frets at `indexFret`, or `nil`
    /// if any fingered fret would fall off the board.
    private static func absoluteFrets(_ shape: MoveableShape, indexFret: Int, board: Fretboard) -> [Int?]? {
        var frets: [Int?] = []
        for offset in shape.relativeFrets {
            guard let offset else {
                frets.append(nil)            // muted string stays muted
                continue
            }
            let fret = indexFret + offset
            guard fret >= 0, fret <= board.fretCount else { return nil }
            frets.append(fret)
        }
        return frets
    }

    // MARK: - The shapes, per quality
    //
    // Each pattern is low → high (E A D G B E). `0` is the index fret (the barre);
    // `nil` is muted. The `rootString` is where the chord root sits at the index
    // fret. These are the standard CAGED "E-shape" (root on the 6th string) and
    // "A-shape" (root on the 5th string) forms — the two that cover almost every
    // moveable chord a player reaches for. At index fret 0 they ARE the open
    // E/A-family chords (e.g. the E-shape major at fret 0 is the open E chord).

    /// The moveable shapes available for a quality (possibly empty → caller falls
    /// back to the generator).
    static func shapes(for quality: ChordQuality) -> [MoveableShape] {
        switch quality {
        case .major:
            return [
                MoveableShape(quality: .major, name: "E-shape", rootString: 0,
                              relativeFrets: [0, 2, 2, 1, 0, 0]),
                MoveableShape(quality: .major, name: "A-shape", rootString: 1,
                              relativeFrets: [nil, 0, 2, 2, 2, 0]),
            ]
        case .minor:
            return [
                MoveableShape(quality: .minor, name: "Em-shape", rootString: 0,
                              relativeFrets: [0, 2, 2, 0, 0, 0]),
                MoveableShape(quality: .minor, name: "Am-shape", rootString: 1,
                              relativeFrets: [nil, 0, 2, 2, 1, 0]),
            ]
        case .dominantSeventh:
            return [
                MoveableShape(quality: .dominantSeventh, name: "E7-shape", rootString: 0,
                              relativeFrets: [0, 2, 0, 1, 0, 0]),
                MoveableShape(quality: .dominantSeventh, name: "A7-shape", rootString: 1,
                              relativeFrets: [nil, 0, 2, 0, 2, 0]),
            ]
        case .majorSeventh:
            return [
                MoveableShape(quality: .majorSeventh, name: "Emaj7-shape", rootString: 0,
                              relativeFrets: [0, 2, 1, 1, 0, 0]),
                MoveableShape(quality: .majorSeventh, name: "Amaj7-shape", rootString: 1,
                              relativeFrets: [nil, 0, 2, 1, 2, 0]),
            ]
        case .minorSeventh:
            return [
                MoveableShape(quality: .minorSeventh, name: "Em7-shape", rootString: 0,
                              relativeFrets: [0, 2, 0, 0, 0, 0]),
                MoveableShape(quality: .minorSeventh, name: "Am7-shape", rootString: 1,
                              relativeFrets: [nil, 0, 2, 0, 1, 0]),
            ]
        case .sus4:
            return [
                MoveableShape(quality: .sus4, name: "Esus4-shape", rootString: 0,
                              relativeFrets: [0, 2, 2, 2, 0, 0]),
                MoveableShape(quality: .sus4, name: "Asus4-shape", rootString: 1,
                              relativeFrets: [nil, 0, 2, 2, 3, 0]),
            ]
        case .sus2:
            return [
                MoveableShape(quality: .sus2, name: "Asus2-shape", rootString: 1,
                              relativeFrets: [nil, 0, 2, 2, 0, 0]),
            ]
        case .sixth:
            return [
                MoveableShape(quality: .sixth, name: "E6-shape", rootString: 0,
                              relativeFrets: [0, 2, 2, 1, 2, 0]),
                MoveableShape(quality: .sixth, name: "A6-shape", rootString: 1,
                              relativeFrets: [nil, 0, 2, 2, 2, 2]),
            ]
        case .minorSixth:
            return [
                MoveableShape(quality: .minorSixth, name: "Em6-shape", rootString: 0,
                              relativeFrets: [0, 2, 2, 0, 2, 0]),
                MoveableShape(quality: .minorSixth, name: "Am6-shape", rootString: 1,
                              relativeFrets: [nil, 0, 2, 2, 1, 2]),
            ]
        default:
            // Qualities without a hand-authored moveable form (diminished, augmented,
            // extended 9/11/13 chords, etc.) fall through to the generator.
            return []
        }
    }
}
