//
//  ScalesViewModel.swift
//  GuitarKit — Scales tool
//
//  The observable state behind the Scales tool: the chosen root + scale, the
//  active tuning + capo, the display toggles (handedness, label mode, orientation,
//  Current ⇄ Standard override), and the computed `FretboardScale` the view
//  highlights. Playback (ascending/descending) is here too, driven by the tone
//  generator.
//
//  The musical truth lives in the PURE `Fretboard`/`FretboardScale` engine; this
//  class just holds the user's choices and recomputes the projection on demand.
//

import Observation
import Foundation

@MainActor
@Observable
final class ScalesViewModel {

    /// How in-scale frets are labeled — the shared toggle both tools use.
    typealias LabelMode = ToolLabelMode

    // MARK: User choices

    var root: PitchClass = .c
    var scaleType: ScaleType = .major
    var capo: Capo = .none

    /// `Current ⇄ Standard` override: when true, map against the instrument's
    /// standard tuning instead of the (possibly custom) current one.
    var useStandardOverride = false

    /// Global left-handed mirror (flips the fret columns).
    var isLeftHanded = false
    /// Note names vs scale degrees on the dots.
    var labelMode: LabelMode = .noteNames
    /// Flip which string sits on top (orientation flip).
    var orientationFlipped = false

    /// How many frets the board shows.
    let fretCount = 12

    // MARK: Tunings
    //
    // The Scales tool is TUNING-AWARE: the highlighted notes reflect the instrument
    // + tuning the player chose in the Tuner (e.g. Drop D). The derivation lives in
    // the shared `InstrumentTuningContext` (the SAME logic the Chords tool uses), so
    // a tuning change in the Tuner re-renders the Scales board automatically.
    @ObservationIgnored private let tuningContext: InstrumentTuningContext

    /// The instrument currently in effect (shared selection / pinned / default).
    var currentInstrument: Instrument { tuningContext.currentInstrument }

    /// The instrument's STANDARD (home) tuning — what the `Current ⇄ Standard`
    /// override maps against.
    var standardTuning: Tuning { tuningContext.standardTuning }

    /// The tuning the player is actually on (preset → custom → standard).
    var currentTuning: Tuning { tuningContext.currentTuning }

    // MARK: Audio (playback)

    @ObservationIgnored private let tonePlayer = ToolTonePlayer()

    // MARK: Init

    /// - Parameters:
    ///   - instrument: supplies the standard tuning (default = standard guitar).
    ///   - currentTuning: the active tuning to map against; defaults to standard.
    init(
        selection: InstrumentSelectionStore? = nil,
        instrument: Instrument? = nil,
        currentTuning: Tuning? = nil
    ) {
        self.tuningContext = InstrumentTuningContext(
            selection: selection,
            instrument: instrument,
            currentTuning: currentTuning
        )
    }

    // MARK: Derived

    /// The tuning currently in effect (honoring the override toggle).
    var activeTuning: Tuning { useStandardOverride ? standardTuning : currentTuning }

    /// The tuning-/capo-aware board.
    var fretboard: Fretboard {
        Fretboard(tuning: activeTuning, capo: capo, fretCount: fretCount)
    }

    /// The scale projected onto that board — what the view highlights.
    var fretboardScale: FretboardScale {
        FretboardScale(fretboard: fretboard, scale: Scale(root: root, type: scaleType))
    }

    /// The label for an in-scale position (or nil when not in scale).
    func label(string: Int, fret: Int) -> String? {
        label(string: string, fret: fret, in: fretboardScale)
    }

    /// Same, but against an ALREADY-COMPUTED `FretboardScale`. The view computes
    /// the scale ONCE per render and passes it to every cell, instead of each
    /// cell rebuilding it (which rebuilt the board + scale ~78× per render).
    func label(string: Int, fret: Int, in fs: FretboardScale) -> String? {
        guard fs.isInScale(string: string, fret: fret) else { return nil }
        switch labelMode {
        case .noteNames:
            return fs.fretboard.note(string: string, fret: fret)?.pitchClass.name
        case .degrees:
            return fs.degree(string: string, fret: fret).map(String.init)
        }
    }

    // MARK: Playback

    /// Each scale note plays for ~220 ms before the next; no extra ring-out (a
    /// stepwise scale wants an even cadence, so the last note stops after its gap).
    func playAscending()  { tonePlayer.play(fretboardScale.ascendingNotes(), gapMs: 220) }
    func playDescending() { tonePlayer.play(fretboardScale.descendingNotes(), gapMs: 220) }
    func stopPlayback()   { tonePlayer.stop() }
}
