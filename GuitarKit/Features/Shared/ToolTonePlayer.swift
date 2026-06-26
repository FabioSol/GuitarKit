//
//  ToolTonePlayer.swift
//  GuitarKit — shared tool support
//
//  The note-playback the Chords and Scales tools share. Both sound a list of notes
//  one after another through a single `ToneGenerator` (our one-voice oscillator),
//  switching the audio session to playback first and cancelling any prior playback.
//  Scales plays a scale up/down; Chords plays a voicing as a fast (block) or slower
//  (strum) arpeggio. Those differ only in the GAP between onsets and an optional
//  ring-out TAIL — captured here as parameters so the two view models don't each
//  re-implement the same task loop.
//
//  HONEST AUDIO LIMITATION: `ToneGenerator` holds ONE pitch at a time, so a "block
//  chord" is really a very fast arpeggio. See `ChordsViewModel` for the full note.
//

import Foundation

@MainActor
final class ToolTonePlayer {

    /// Each tool owns its own generator + session coordinator so the tools don't
    /// fight over the shared audio session.
    private let tone = ToneGenerator()
    private let chordPlayer = PolyphonicTonePlayer()
    private let coordinator = AudioSessionCoordinator()
    private var playTask: Task<Void, Never>?

    /// Play `notes` sequentially, `gapMs` between onsets, then — if `tailMs` > 0
    /// — let the final note ring that long before stopping. Used for scale runs
    /// and strum arpeggios. Cancels any in-flight playback first.
    ///
    /// - Parameters:
    ///   - notes: the notes to sound, in order.
    ///   - referenceA: A4 calibration for frequency resolution (defaults to 440).
    ///   - gapMs: milliseconds between successive note onsets.
    ///   - tailMs: extra ring-out after the last onset.
    func play(_ notes: [Note], referenceA: ReferencePitch? = nil, gapMs: Int, tailMs: Int = 0) {
        playTask?.cancel()
        chordPlayer.stop()
        try? coordinator.configureForPlayback()
        guard !notes.isEmpty else { return }

        let calculator = PitchCalculator(referenceA: referenceA ?? .standard)
        playTask = Task { @MainActor in
            for note in notes {
                if Task.isCancelled { break }
                self.tone.play(frequencyHz: calculator.frequency(of: note))
                try? await Task.sleep(for: .milliseconds(gapMs))
            }
            if tailMs > 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(tailMs))
            }
            self.tone.stop()
        }
    }

    /// Play `notes` simultaneously as a true chord, all voices starting at once.
    /// Lets the chord ring for `tailMs` then fades out. Used for the Chords tool's
    /// block-chord playback.
    func playChord(_ notes: [Note], referenceA: ReferencePitch? = nil, tailMs: Int) {
        playTask?.cancel()
        tone.stop()
        try? coordinator.configureForPlayback()
        guard !notes.isEmpty else { return }

        let calculator = PitchCalculator(referenceA: referenceA ?? .standard)
        let frequencies = notes.map { calculator.frequency(of: $0) }
        chordPlayer.play(frequencies: frequencies)

        playTask = Task { @MainActor in
            if tailMs > 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(tailMs))
            }
            self.chordPlayer.stop()
        }
    }

    /// Stop any in-progress playback immediately.
    func stop() {
        playTask?.cancel()
        tone.stop()
        chordPlayer.stop()
    }
}
