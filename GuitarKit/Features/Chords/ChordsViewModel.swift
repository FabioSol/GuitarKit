//
//  ChordsViewModel.swift
//  GuitarKit — Chords tool
//
//  The observable state behind the Chords tool: the chosen root + quality, the
//  active tuning + capo, the display toggles (handedness, label mode, the
//  Current ⇄ Standard override), which alternate voicing is selected, and the
//  computed `ChordVoicing` the view draws. Playback (block or strummed) lives
//  here too, driven by the tone generator.
//
//  The musical truth lives in the PURE engines — `Fretboard`,
//  `ChordVoicingGenerator`, and `StandardChordLibrary`. This class just holds the
//  user's choices and recomputes the projection on demand, mirroring how
//  `ScalesViewModel` sits on top of `FretboardScale`.
//

import Observation
import Foundation

@MainActor
@Observable
final class ChordsViewModel {

    /// How the notes in the chord box are labeled. Mirrors `ScalesViewModel
    /// .LabelMode` so the two sibling tools feel identical:
    ///   • `.noteNames` → "C", "E", "G" on the dots.
    ///   • `.degrees`   → the chord degree ("1", "3", "5", "♭7"…).
    enum LabelMode: CaseIterable, Hashable { case noteNames, degrees }

    // MARK: User choices

    var root: PitchClass = .c
    var quality: ChordQuality = .major
    var capo: Capo = .none

    /// `Current ⇄ Standard` override: when true, build the voicing against the
    /// instrument's standard tuning instead of the (possibly custom) current one.
    var useStandardOverride = false

    /// Global left-handed mirror (flips the string columns in the chord box).
    var isLeftHanded = false

    /// Note names vs chord degrees on the dots.
    var labelMode: LabelMode = .noteNames

    /// Which alternate voicing the user is looking at (an index into
    /// `alternateVoicings`). `cycleVoicing()` advances it; it auto-clamps whenever
    /// the chord changes so we never index past the end of a shorter list.
    var voicingIndex = 0

    /// How many frets the chord box shows. Five is the conventional chord-box
    /// height (a nut plus four fret rows), enough for every open shape and most
    /// moveable ones.
    let fretCount = 5

    // MARK: Tunings

    @ObservationIgnored let currentTuning: Tuning
    @ObservationIgnored let standardTuning: Tuning

    // MARK: Audio (playback)
    //
    // Each tool owns its OWN tone generator + session coordinator so the tools
    // don't fight over the shared audio session — this copies the pattern from
    // `ScalesViewModel` exactly.

    @ObservationIgnored private let tone = ToneGenerator()
    @ObservationIgnored private let coordinator = AudioSessionCoordinator()
    @ObservationIgnored private var playTask: Task<Void, Never>?

    // MARK: Init

    /// - Parameters:
    ///   - instrument: supplies the standard tuning (default = standard guitar).
    ///   - currentTuning: the active tuning to voice against; defaults to standard.
    ///
    /// THE MAIN-ACTOR GOTCHA: in this main-actor-by-default project we must NOT use
    /// a main-actor-isolated value (like `InstrumentLibrary.default`) as a DEFAULT
    /// ARGUMENT — that warns. So both params default to `nil` and we resolve the
    /// real defaults INSIDE the init body, exactly as `ScalesViewModel` does.
    init(instrument: Instrument? = nil, currentTuning: Tuning? = nil) {
        let instrument = instrument ?? InstrumentLibrary.default
        let standard = instrument.defaultTuning
            ?? Tuning(name: "Standard", category: .standard, strings: [])
        self.standardTuning = standard
        self.currentTuning = currentTuning ?? standard
    }

    // MARK: Derived — tuning & board

    /// The tuning currently in effect (honoring the override toggle).
    var activeTuning: Tuning { useStandardOverride ? standardTuning : currentTuning }

    /// The tuning-/capo-aware board the voicing is generated on.
    var fretboard: Fretboard {
        Fretboard(tuning: activeTuning, capo: capo, fretCount: fretCount)
    }

    /// The chord the user picked, as a pure `Chord` (root + quality).
    var chord: Chord { Chord(root: root, quality: quality) }

    // MARK: Derived — voicings

    /// All the voicings the user can cycle through, low → high up the neck.
    ///
    /// THE FALLBACK RULE (the spec's "curated library as a fallback where
    /// generation is weak"): when we're in standard guitar tuning WITH NO CAPO and
    /// the library has a hand-authored shape for this chord, we put that curated
    /// shape FIRST so the default the user sees is the familiar open chord. The
    /// generator's alternates follow it for cycling up the neck. In any other
    /// tuning (or with a capo, which moves the open pitches) we use the generator
    /// alone.
    ///
    /// Computed fresh each access — cheap pure work, and it means changing root,
    /// quality, tuning, or capo instantly reflows the list.
    var alternateVoicings: [ChordVoicing] {
        let generated = ChordVoicingGenerator.alternates(for: chord, on: fretboard)

        // The library is only valid for un-capo'd standard guitar tuning.
        let canUseLibrary = !capo.isEngaged
            && StandardChordLibrary.isStandardGuitar(openStrings: fretboard.openStrings)

        guard canUseLibrary,
              let curated = StandardChordLibrary.voicing(root: root, quality: quality)
        else {
            // No curated shape (or wrong tuning): the generator stands alone. If it
            // somehow produced nothing, hand back a single all-muted placeholder so
            // the view always has one voicing to render.
            return generated.isEmpty
                ? [ChordVoicing(frets: Array(repeating: nil, count: fretboard.stringCount))]
                : generated
        }

        // Put the curated open shape first, then the generated alternates that
        // aren't duplicates of it, so cycling moves up the neck from the open shape.
        var result = [curated]
        result.append(contentsOf: generated.filter { $0 != curated })
        return result
    }

    /// The voicing currently on screen — `alternateVoicings` indexed by the
    /// (clamped) `voicingIndex`. Clamping guards against a stale index after the
    /// chord changes to one with fewer alternates.
    var currentVoicing: ChordVoicing {
        let list = alternateVoicings
        guard !list.isEmpty else {
            return ChordVoicing(frets: Array(repeating: nil, count: fretboard.stringCount))
        }
        let safeIndex = min(max(0, voicingIndex), list.count - 1)
        return list[safeIndex]
    }

    /// How many distinct voicings exist for the current chord (for "1 of 3"–style
    /// UI and to decide whether the cycle button does anything).
    var voicingCount: Int { alternateVoicings.count }

    /// Advance to the next voicing up the neck, wrapping back to the first after
    /// the last. Wrapping (rather than stopping) makes the cycle button feel
    /// endless, which is what "cycle through alternate voicings" implies.
    func cycleVoicing() {
        let count = voicingCount
        guard count > 0 else { return }
        voicingIndex = (voicingIndex + 1) % count
    }

    /// Reset the cycle back to the first (lowest) voicing. The view calls this when
    /// the user changes root or quality, so they always land on the default shape
    /// rather than mid-cycle on a stale index.
    func resetVoicing() { voicingIndex = 0 }

    // MARK: Labels

    /// The label to draw on the dot for a given string in the CURRENT voicing, or
    /// `nil` if that string is muted (no dot to label).
    ///
    /// `.noteNames` reads the note off the board at the chosen fret; `.degrees`
    /// works out which chord tone it is (1, 3, 5, ♭7…) from the chord's recipe.
    func label(forString string: Int) -> String? {
        let voicing = currentVoicing
        guard string < voicing.frets.count,
              let fret = voicing.frets[string],
              let note = fretboard.note(string: string, fret: fret)
        else { return nil }

        switch labelMode {
        case .noteNames:
            return note.pitchClass.name
        case .degrees:
            return degreeLabel(for: note.pitchClass)
        }
    }

    /// Translate a sounding pitch class into a chord-degree label ("1", "3", "5",
    /// "♭7"…). We find the chord interval (semitone distance from the root) and map
    /// the common ones to their familiar degree names; anything unexpected falls
    /// back to the raw semitone number so we never show a blank.
    private func degreeLabel(for pitchClass: PitchClass) -> String {
        let semitones = pitchClass.semitoneDistance(from: root)
        switch semitones {
        case 0:  return "1"
        case 1:  return "♭9"
        case 2:  return "9"
        case 3:  return "♭3"
        case 4:  return "3"
        case 5:  return "11"
        case 6:  return "♭5"
        case 7:  return "5"
        case 8:  return "♯5"
        case 9:  return "6"
        case 10: return "♭7"
        case 11: return "7"
        default: return "\(semitones)"
        }
    }

    // MARK: Playback

    /// Play the current voicing as a BLOCK chord — all notes "together".
    ///
    /// HONEST AUDIO LIMITATION: our `ToneGenerator` can only sound ONE pitch at a
    /// time (it's a single oscillator built for the tuner's "tap a peg" tone). A
    /// true simultaneous block chord would need a polyphonic synth we don't have
    /// here. So "block" is implemented as a VERY fast arpeggio (~10 ms between
    /// notes) — fast enough to read as a single strum-stab — and "strum" as a
    /// slower one (~40 ms) you can hear roll low → high. It's a deliberate,
    /// documented approximation, not the real thing.
    func playBlock() { playArpeggio(staggerMs: 10) }

    /// Play the current voicing as a STRUM: the same notes, but staggered ~40 ms
    /// apart low → high so you hear the pick sweep across the strings.
    func playStrum() { playArpeggio(staggerMs: 40) }

    /// Stop any in-progress playback immediately.
    func stopPlayback() { playTask?.cancel(); tone.stop() }

    /// Shared playback engine for block/strum: sound the voicing's notes low → high
    /// with `staggerMs` between onsets, then let the final note ring briefly.
    ///
    /// Because a single `ToneGenerator` can't hold multiple pitches, each new note
    /// retargets the same oscillator. That means you mostly hear the LAST note
    /// sustain rather than a true chord — again, an honest limitation of the
    /// one-voice generator. The low-to-high sweep is what sells "this is a chord
    /// being strummed."
    private func playArpeggio(staggerMs: Int) {
        playTask?.cancel()
        try? coordinator.configureForPlayback()

        // Only the strings that actually sound, low → high, as concrete notes.
        let notes = currentVoicing.playedNotes(on: fretboard)
        guard !notes.isEmpty else { return }

        let calculator = PitchCalculator()
        playTask = Task { @MainActor in
            for note in notes {
                if Task.isCancelled { break }
                tone.play(frequencyHz: calculator.frequency(of: note))
                try? await Task.sleep(for: .milliseconds(staggerMs))
            }
            // Let the chord ring a beat after the last onset, then release.
            if !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(450))
            }
            tone.stop()
        }
    }
}
