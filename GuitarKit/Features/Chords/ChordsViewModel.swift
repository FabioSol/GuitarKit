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

    /// How the notes in the chord box are labeled — the shared toggle both tools
    /// use, so Chords and Scales feel identical.
    typealias LabelMode = ToolLabelMode

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

    /// How many frets of NECK the voicing search runs over. This is the board
    /// length, NOT the diagram height — the diagram shows a sliding 5-fret window
    /// onto this neck (see `ChordsView.visibleFretCount`). A full octave gives the
    /// generator room to find alternate shapes UP the neck for the "next voicing"
    /// cycle; the view then windows + labels them with a position number ("5fr").
    let fretCount = 12

    // MARK: Tunings
    //
    // The Chords tool is TUNING-AWARE: its voicings reflect whatever instrument +
    // tuning the player has chosen in the Tuner (e.g. Drop D). The derivation lives
    // in the shared `InstrumentTuningContext` (the SAME logic the Scales tool uses),
    // so when the player's selection changes the Chords screen reflows automatically.
    @ObservationIgnored private let tuningContext: InstrumentTuningContext

    /// The instrument currently in effect (shared selection / pinned / default).
    var currentInstrument: Instrument { tuningContext.currentInstrument }

    /// The instrument's STANDARD (home) tuning — what the `Current ⇄ Standard`
    /// override compares against. For a guitar this is EADGBE.
    var standardTuning: Tuning { tuningContext.standardTuning }

    /// The tuning the player is actually on (preset → custom → standard).
    var currentTuning: Tuning { tuningContext.currentTuning }

    // MARK: Audio (playback)

    @ObservationIgnored private let tonePlayer = ToolTonePlayer()

    // MARK: Init

    /// - Parameters:
    ///   - instrument: supplies the standard tuning (default = standard guitar).
    ///   - currentTuning: the active tuning to voice against; defaults to standard.
    init(
        selection: InstrumentSelectionStore? = nil,
        customTunings: CustomTuningStore? = nil,
        instrument: Instrument? = nil,
        currentTuning: Tuning? = nil
    ) {
        self.tuningContext = InstrumentTuningContext(
            selection: selection,
            customTunings: customTunings,
            instrument: instrument,
            currentTuning: currentTuning
        )
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
    /// THE PLAYABILITY RULE: in standard guitar tuning (no capo) we build the list
    /// from KNOWN-GOOD shapes only — the curated OPEN shape (`StandardChordLibrary`,
    /// the familiar nut-position chord) plus the moveable BARRE shapes
    /// (`MoveableChordLibrary`, slid up the neck by transposition). That guarantees
    /// every shape we show is actually fingerable and idiomatic, instead of the raw
    /// generator's note-by-note search, which could emit unplayable five-finger
    /// shapes. We only fall back to the generator (filtered to playable shapes) when
    /// those banks have nothing for this chord — an uncommon quality — or when the
    /// tuning/capo isn't standard guitar, where the fixed shapes don't apply.
    ///
    /// Computed fresh each access — cheap pure work, and it means changing root,
    /// quality, tuning, or capo instantly reflows the list.
    var alternateVoicings: [ChordVoicing] {
        let board = fretboard

        // The fixed shapes are only valid for un-capo'd standard guitar tuning.
        let canUseShapes = !capo.isEngaged
            && StandardChordLibrary.isStandardGuitar(openStrings: board.openStrings)

        if canUseShapes {
            var result: [ChordVoicing] = []
            // 1) The familiar open shape first (if curated), so the default the user
            //    lands on is the nut-position chord they know.
            if let curated = StandardChordLibrary.voicing(root: root, quality: quality) {
                result.append(curated)
            }
            // 2) Moveable barre shapes up the neck, de-duplicated against the open one.
            for voicing in MoveableChordLibrary.voicings(root: root, quality: quality, on: board)
            where !result.contains(voicing) {
                result.append(voicing)
            }
            if !result.isEmpty {
                // Order low → high so cycling climbs from the open/lowest shape.
                return result.sorted { ($0.lowestFrettedFret ?? 0) < ($1.lowestFrettedFret ?? 0) }
            }
            // Nothing in the banks for this chord → fall through to the generator.
        }

        // FALLBACK: the generator, filtered to drop the physically unplayable shapes
        // it can produce. If everything was filtered out (or it produced nothing),
        // hand back a single all-muted placeholder so the view always has one
        // voicing to render.
        let generated = ChordVoicingGenerator.alternates(for: chord, on: board)
            .filter { ChordVoicingGenerator.isPlayable($0, on: board) }
        return generated.isEmpty
            ? [ChordVoicing(frets: Array(repeating: nil, count: board.stringCount))]
            : generated
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

    /// A spoken description of the current voicing for VoiceOver (slice #23). The
    /// chord box is otherwise a purely VISUAL grid of dots, invisible to a screen
    /// reader; this turns it into one element that reads the chord name plus a
    /// per-string, low → high account ("low E muted, A string 3rd fret…"). Using
    /// each string's open-note name makes it a guitarist-friendly read.
    var voicingAccessibilityDescription: String {
        let name = "\(root.name)\(quality.symbol)"
        let board = fretboard
        let frets = currentVoicing.frets
        var parts: [String] = []
        for string in 0..<board.stringCount {
            let openName = board.openStrings[string].pitchClass.name
            let fret = string < frets.count ? frets[string] : nil
            switch fret {
            case .none:        parts.append("\(openName) string muted")
            case .some(0):     parts.append("\(openName) string open")
            case .some(let f): parts.append("\(openName) string fret \(f)")
            }
        }
        let counter = voicingCount > 1 ? " Voicing \(voicingIndex + 1) of \(voicingCount)." : ""
        return "\(name) chord.\(counter) " + parts.joined(separator: ", ")
    }

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
        label(forString: string, in: currentVoicing, board: fretboard)
    }

    /// Same, but against an ALREADY-COMPUTED voicing + board, so the view can
    /// resolve them ONCE per render and pass them to every cell instead of each
    /// cell rebuilding the voicing (which re-ran the generator + library ~36×).
    func label(forString string: Int, in voicing: ChordVoicing, board: Fretboard) -> String? {
        guard string < voicing.frets.count,
              let fret = voicing.frets[string],
              let note = board.note(string: string, fret: fret)
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

    /// Play the current voicing as a true block chord: all notes sounding
    /// simultaneously through a polyphonic oscillator mix.
    func playBlock() {
        tonePlayer.playChord(currentVoicing.playedNotes(on: fretboard), tailMs: 600)
    }

    /// Play the current voicing as a strum: notes low → high, ~40 ms apart, so
    /// you hear the pick sweep across the strings.
    func playStrum() { playArpeggio(staggerMs: 40) }

    /// Stop any in-progress playback immediately.
    func stopPlayback() { tonePlayer.stop() }

    private func playArpeggio(staggerMs: Int) {
        tonePlayer.play(currentVoicing.playedNotes(on: fretboard), gapMs: staggerMs, tailMs: 450)
    }
}
