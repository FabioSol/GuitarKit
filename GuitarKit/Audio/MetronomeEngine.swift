//
//  MetronomeEngine.swift
//  GuitarKit
//
//  The real-time playback side of the metronome. It plays a steady, DRIFT-FREE
//  click at a fixed tempo by PRE-SCHEDULING click buffers at exact sample times
//  on an `AVAudioPlayerNode` — never a `Timer` (which is at the mercy of the run
//  loop and drifts). The "when does each beat happen?" math is the pure,
//  unit-tested `MetronomeSequencer`; this class only turns those sample offsets
//  into scheduled audio.
//
//  HOW PRE-SCHEDULING STAYS DRIFT-FREE:
//  `AVAudioPlayerNode.scheduleBuffer(_:at:)` lets us say "play this click at
//  sample N of your timeline." The audio hardware advances that timeline on its
//  own rock-steady clock, so a click scheduled at sample 22050 plays at exactly
//  that instant. We schedule a small ROLLING WINDOW of upcoming beats up front,
//  and each time a beat finishes we schedule one more — so the queue never runs
//  dry, and every beat's time comes from `MetronomeSequencer` (anchored to beat
//  0), not from wall-clock arithmetic.
//
//  Tempo is FIXED per start (time signatures / subdivisions / accents are later
//  slices). Changing `bpm` takes effect the next time you `start()`.
//

import AVFoundation
import Observation

@MainActor
@Observable
final class MetronomeEngine {

    // MARK: Public state

    /// Tempo in beats per minute. Read by the (future) metronome face; applied on
    /// the next `start()`.
    var bpm: Double = 120

    /// Whether the click is currently running. `private(set)` — the engine writes
    /// it, the UI reads it.
    private(set) var isPlaying = false

    // MARK: Audio machinery (plumbing, not observed)

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var clickBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var isSetUp = false
    @ObservationIgnored private var sampleRate: Double = 44_100

    /// How many beats we keep scheduled ahead of "now". A small cushion so the
    /// queue never empties between a beat finishing and the next being scheduled.
    @ObservationIgnored private let scheduleWindow = 8

    /// The index of the next beat we still need to schedule. Advances as beats
    /// play and we top the window up.
    @ObservationIgnored private var nextBeatToSchedule = 0

    init() {}

    // MARK: Lifecycle

    /// Start the click from beat 0 (an immediate downbeat) at the current `bpm`.
    func start() {
        guard !isPlaying else { return }
        do {
            try setUpIfNeeded()
        } catch {
            // If the playback graph can't start there's nothing to click. Fail
            // quietly; a future face can surface an error.
            return
        }

        nextBeatToSchedule = 0
        isPlaying = true

        // Pre-schedule the initial window, then start the node. (Beat 0's sample
        // offset is 0, so it sounds the instant playback begins.)
        for _ in 0..<scheduleWindow {
            scheduleNextBeat()
        }
        player.play()
    }

    /// Stop the click and clear anything still queued.
    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        player.stop()
        // `stop()` already flushes scheduled buffers; reset our bookkeeping so the
        // next start begins cleanly at beat 0.
        nextBeatToSchedule = 0
    }

    /// Fully tear down the audio graph (e.g. when leaving the Metronome tool).
    func shutdown() {
        stop()
        if isSetUp {
            engine.stop()
            isSetUp = false
        }
    }

    // MARK: Scheduling

    /// Build the audio graph and the click buffer once.
    private func setUpIfNeeded() throws {
        guard !isSetUp else {
            // Engine exists but may have been stopped by a previous shutdown.
            if !engine.isRunning { try engine.start() }
            return
        }

        // The format we'll synthesize and connect in — the output's own format.
        let format = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        clickBuffer = ClickSound.buffer(format: format)

        engine.prepare()
        try engine.start()
        isSetUp = true
    }

    /// Schedule the click for `nextBeatToSchedule` at its exact sample time, then
    /// advance. Each scheduled buffer's completion (when it has played back) tops
    /// the window up with the following beat — so the queue stays `scheduleWindow`
    /// beats deep without ever consulting wall-clock time.
    private func scheduleNextBeat() {
        guard let clickBuffer else { return }

        let beat = nextBeatToSchedule
        nextBeatToSchedule += 1

        // The drift-free sample offset of this beat (anchored to beat 0).
        let offset = MetronomeSequencer.sampleOffset(ofBeat: beat, bpm: bpm, sampleRate: sampleRate)
        let when = AVAudioTime(sampleTime: AVAudioFramePosition(offset), atRate: sampleRate)

        player.scheduleBuffer(clickBuffer, at: when, options: [],
                              completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // Fires on an audio thread once this beat has played. Hop to the main
            // actor and, if we're still running, queue one more beat to refill the
            // window.
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.scheduleNextBeat()
            }
        }
    }
}
