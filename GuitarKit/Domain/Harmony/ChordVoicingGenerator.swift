//
//  ChordVoicingGenerator.swift
//  GuitarKit — Harmony domain
//
//  A PURE, deterministic voicing generator. Given a `Chord` (which pitch classes
//  to sound) and a `Fretboard` (the tuning/capo we're playing in), it searches
//  the neck for a reasonable, PLAYABLE shape — one fret per string whose note is
//  a chord tone — and returns it as a `ChordVoicing`.
//
//  HONEST FRAMING: this is a HEURISTIC, not a world-class chord-voicing engine.
//  Professional voicers weigh finger independence, voice-leading, doublings,
//  omitted fifths, idiomatic shapes, etc. We do something far simpler but useful:
//  for each string, pick the LOWEST chord-tone fret that falls inside a small
//  sliding window (so the shape stays under one hand), preferring the chord's
//  ROOT in the bass, and muting strings that can't contribute cleanly. The result
//  is in-chord and physically reachable, which is exactly what the Chords tool
//  needs as its "generated from the string pitches" default. Where this comes out
//  thin (sparse, lots of muted strings), the view-model falls back to the curated
//  `StandardChordLibrary` for standard tuning.
//
//  WHY DETERMINISTIC? No randomness anywhere — the same chord + board + minimum
//  fret always yields the same voicing. That's what makes it unit-testable (the
//  spec requires generation to be covered by tests) and what lets the UI "cycle"
//  predictably up the neck.
//
//  No SwiftUI / AVFoundation here — pure value logic.
//

import Foundation

/// Generates playable chord shapes for a chord on a given fretboard.
///
/// WHY AN ENUM NAMESPACE (no instances)?
/// The generator holds no state of its own — it's a set of pure functions that
/// turn inputs into a `ChordVoicing`. An empty `enum` can never be instantiated,
/// which says "this is a bag of static functions" more honestly than a `struct`
/// you'd never give stored properties. Callers write
/// `ChordVoicingGenerator.voicing(for:on:)`.
public enum ChordVoicingGenerator {

    // MARK: - Tuning knobs for the heuristic
    //
    // Named constants (rather than magic numbers buried in the code) so the
    // heuristic's behavior is legible and easy to tweak in one place.

    /// The widest fret SPAN a single shape may cover, fingered notes only. Four
    /// frets is the classic "one hand without stretching" window a beginner can
    /// reach, so we keep every fingered note within `windowSpan` of the lowest.
    public static let windowSpan = 4

    /// How many distinct fret POSITIONS we try when asked for "alternates up the
    /// neck": one starting at each successive minimum fret. Twelve covers a whole
    /// octave of positions, which is plenty for cycling.
    private static let positionsToScan = 12

    // MARK: - Public API

    /// Generate the BEST single voicing for `chord` on `fretboard`, searching from
    /// `minimumFret` upward. This is the everyday entry point: the view-model calls
    /// it with `minimumFret: 0` for the default open-ish shape.
    ///
    /// - Parameters:
    ///   - chord: which pitch classes the shape must be drawn from.
    ///   - fretboard: the tuning/capo-aware board to find frets on.
    ///   - minimumFret: the lowest fret the window may start at (0 = include open
    ///     strings). Raising this is how we get shapes higher up the neck.
    /// - Returns: a playable `ChordVoicing`. It always returns *something*
    ///   (possibly sparse) so the caller never has to handle a "no shape" case;
    ///   the caller decides whether the shape is too thin to use.
    public static func voicing(
        for chord: Chord,
        on fretboard: Fretboard,
        minimumFret: Int = 0
    ) -> ChordVoicing {
        // The window runs [windowStart ... windowStart + windowSpan]. We never let
        // it run off the end of the board.
        let windowStart = max(0, minimumFret)
        let windowEnd = min(fretboard.fretCount, windowStart + windowSpan)

        // The chord-tone test, computed once: a fret is "in chord" if the note it
        // sounds has a pitch class in this set.
        let tones = chord.pitchClassSet

        // STEP 1 — pick a fret for every string independently.
        //
        // For each string, scan its frets within the window and keep the LOWEST
        // one whose note is a chord tone. Open strings (fret 0) are allowed only
        // when the window starts at 0 — otherwise a "high up the neck" voicing
        // would still ring open strings, which isn't the shape we asked for.
        var chosen: [Int?] = (0..<fretboard.stringCount).map { string in
            lowestChordToneFret(
                onString: string,
                from: windowStart,
                to: windowEnd,
                allowOpen: windowStart == 0,
                tones: tones,
                fretboard: fretboard
            )
        }

        // STEP 2 — prefer the chord ROOT in the bass.
        //
        // A chord sounds most "rooted" when its lowest sounding string is the
        // chord's root (a "root-position" voicing). We walk up from the lowest
        // string and MUTE any sounding strings below the first one that plays the
        // root — but only if doing so doesn't silence the whole shape. This is a
        // gentle nudge, not a hard rule: if no string in the window can play the
        // root, we leave the bass as-is rather than mute everything.
        applyRootInBassPreference(&chosen, root: chord.root, fretboard: fretboard)

        return ChordVoicing(frets: chosen)
    }

    /// Generate a LIST of alternate voicings, ordered low → high up the neck.
    ///
    /// HOW: we ask `voicing(for:on:minimumFret:)` once per starting fret (0, 1,
    /// 2, …) and then de-duplicate. Different minimums often resolve to the same
    /// shape (e.g. minimum 0 and 1 both find the open shape), so we drop repeats
    /// and shapes that are entirely muted. The result is the cycle the UI steps
    /// through; index 0 is the lowest/most-open, later indices climb the neck.
    ///
    /// - Returns: at least one voicing when the chord is playable at all; ordered
    ///   so each later entry sits at the same height or higher than the previous.
    public static func alternates(
        for chord: Chord,
        on fretboard: Fretboard
    ) -> [ChordVoicing] {
        var result: [ChordVoicing] = []

        for minFret in 0..<positionsToScan {
            // Stop scanning once the window can't fit on the board any more.
            guard minFret <= fretboard.fretCount else { break }

            let candidate = voicing(for: chord, on: fretboard, minimumFret: minFret)

            // Skip shapes that sound nothing (fully muted) — not a usable voicing.
            guard !candidate.soundingStringIndices.isEmpty else { continue }

            // Skip a candidate identical to one we already have (common: adjacent
            // minimum frets resolve to the same shape).
            guard !result.contains(candidate) else { continue }

            result.append(candidate)
        }

        // Sort low → high by where the hand sits. Shapes with no fingered note
        // (pure open chords) sort first by treating their height as 0.
        return result.sorted { lhs, rhs in
            (lhs.lowestFrettedFret ?? 0) < (rhs.lowestFrettedFret ?? 0)
        }
    }

    // MARK: - Heuristic building blocks (private)

    /// Find the LOWEST fret on one string, within `[from ... to]`, whose note is a
    /// chord tone — or `nil` if none qualifies (that string then gets muted).
    ///
    /// `allowOpen` gates fret 0: for high-up-the-neck windows we don't want open
    /// strings sneaking into the shape, so the caller passes `false` there.
    private static func lowestChordToneFret(
        onString string: Int,
        from: Int,
        to: Int,
        allowOpen: Bool,
        tones: Set<PitchClass>,
        fretboard: Fretboard
    ) -> Int? {
        // Decide the lowest fret we're allowed to consider on this string.
        let start = allowOpen ? from : max(from, 1)

        // EMPTY-WINDOW GUARD: if the window has collapsed (its end fell below its
        // start — e.g. a `minimumFret` that runs off a short board), there is no
        // fret to consider, so mute this string. Without this the old
        // `start...max(start, to)` quietly scanned `start` itself even when it sat
        // ABOVE the window end, leaning on the `fret <= fretCount` filter to catch
        // it — fragile, and it scanned a fret outside the one-hand span. Making the
        // empty range explicit is clearer and can't scan past the window.
        guard start <= to else { return nil }

        // Scan upward and return the first (= lowest) chord-tone fret we hit.
        // Ascending order matters: "lowest in window" gives the most compact,
        // easiest-to-finger shape, and keeps the bass note as low as possible.
        // `to` is already clamped to the board (`windowEnd = min(fretCount, …)`),
        // so every fret in `start...to` is on the neck.
        for fret in start...to {
            guard let note = fretboard.note(string: string, fret: fret) else { continue }
            if tones.contains(note.pitchClass) {
                return fret
            }
        }
        return nil
    }

    /// Nudge the shape toward "root in the bass": mute any sounding strings BELOW
    /// the lowest string that already plays the chord root.
    ///
    /// We only apply this when at least one string in the shape plays the root —
    /// otherwise muting the bass would just thin the chord for no gain. Mutating
    /// the array in place (`inout`) keeps the call site readable.
    private static func applyRootInBassPreference(
        _ frets: inout [Int?],
        root: PitchClass,
        fretboard: Fretboard
    ) {
        // Find the lowest string index whose chosen fret sounds the root.
        let rootString = frets.indices.first { string in
            guard let fret = frets[string],
                  let note = fretboard.note(string: string, fret: fret) else { return false }
            return note.pitchClass == root
        }

        guard let rootString, rootString > 0 else { return }

        // Mute everything below that root string so the root is the bass note.
        for string in 0..<rootString {
            frets[string] = nil
        }
    }
}
