//
//  ScalesViewModel.swift
//  GuitarKit — Scales tool
//
//  The observable state behind the Scales tool: the chosen root + scale, the
//  active tuning + capo, the display toggles (handedness, label mode, orientation,
//  finger-number flag, Current ⇄ Standard override), and the computed
//  `FretboardScale` the view highlights. Playback (ascending/descending) is here
//  too, driven by the tone generator.
//
//  The musical truth lives in the PURE `Fretboard`/`FretboardScale` engine; this
//  class just holds the user's choices and recomputes the projection on demand.
//

import Observation
import Foundation

@MainActor
@Observable
final class ScalesViewModel {

    /// How in-scale frets are labeled.
    enum LabelMode: CaseIterable, Hashable { case noteNames, degrees }

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
    /// Finger-number labels — behind a flag (default off), since fingering isn't
    /// generated yet; the toggle reserves the behavior for a later pass.
    var showFingerNumbers = false
    /// Flip which string sits on top (orientation flip).
    var orientationFlipped = false

    /// How many frets the board shows.
    let fretCount = 12

    // MARK: Tunings

    @ObservationIgnored let currentTuning: Tuning
    @ObservationIgnored let standardTuning: Tuning

    // MARK: Audio (playback)

    @ObservationIgnored private let tone = ToneGenerator()
    @ObservationIgnored private let coordinator = AudioSessionCoordinator()
    @ObservationIgnored private var playTask: Task<Void, Never>?

    // MARK: Init

    /// - Parameters:
    ///   - instrument: supplies the standard tuning (default = standard guitar).
    ///   - currentTuning: the active tuning to map against; defaults to standard.
    init(instrument: Instrument? = nil, currentTuning: Tuning? = nil) {
        // Resolve the main-actor default inside the init (the project's gotcha).
        let instrument = instrument ?? InstrumentLibrary.default
        let standard = instrument.defaultTuning
            ?? Tuning(name: "Standard", category: .standard, strings: [])
        self.standardTuning = standard
        self.currentTuning = currentTuning ?? standard
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
        let fs = fretboardScale
        guard fs.isInScale(string: string, fret: fret) else { return nil }
        switch labelMode {
        case .noteNames:
            return fretboard.note(string: string, fret: fret)?.pitchClass.name
        case .degrees:
            return fs.degree(string: string, fret: fret).map(String.init)
        }
    }

    // MARK: Playback

    func playAscending()  { playSequence(fretboardScale.ascendingNotes()) }
    func playDescending() { playSequence(fretboardScale.descendingNotes()) }
    func stopPlayback()   { playTask?.cancel(); tone.stop() }

    /// Play a list of notes in sequence, each a brief sustained tone. We switch
    /// the audio session to playback first so the tones are audible.
    private func playSequence(_ notes: [Note]) {
        playTask?.cancel()
        try? coordinator.configureForPlayback()
        let calculator = PitchCalculator()
        playTask = Task { @MainActor in
            for note in notes {
                if Task.isCancelled { break }
                tone.play(frequencyHz: calculator.frequency(of: note))
                try? await Task.sleep(for: .milliseconds(220))
            }
            tone.stop()
        }
    }
}
