//
//  MetronomeEngine.swift
//  GuitarKit
//
//  The real-time playback side of the metronome. It plays a steady, DRIFT-FREE
//  click by PRE-SCHEDULING click buffers at exact sample times on an
//  `AVAudioPlayerNode` — never a `Timer` (which is at the mercy of the run loop
//  and drifts). The "when does each tick happen?" math is the pure, unit-tested
//  `MetronomeSequencer`; this class only turns those sample offsets into
//  scheduled audio.
//
//  WHAT'S NEW IN THE CONFIG SLICE (#16):
//  The engine now schedules TICKS, not just beats. A "tick" is a sub-beat: with
//  `ticksPerBeat` ticks per beat (from the chosen `Subdivision`), every
//  `ticksPerBeat`-th tick lands ON a beat and the others fall BETWEEN beats. For
//  each tick we decide which sound (if any) to play:
//
//    • A tick that lands on a beat looks up that beat's `BeatAccent`:
//        accent → the accent buffer
//        normal → the normal buffer
//        muted  → schedule NOTHING, but STILL advance the tick index
//    • A tick that falls between beats plays the quieter subdivision buffer.
//
//  WHY MUTING DOESN'T BREAK TIMING:
//  Every tick's sample offset is absolute and anchored to tick 0 (via
//  `MetronomeSequencer.tickOffset`). So skipping the buffer for a muted beat
//  leaves a silent gap in EXACTLY the right place — the following ticks keep
//  their anchored offsets and stay perfectly on time. Muting never shifts
//  anything; it just omits a sound.
//
//  HOW PRE-SCHEDULING STAYS DRIFT-FREE (unchanged):
//  `scheduleBuffer(_:at:)` lets us say "play this at sample N of your timeline."
//  The audio hardware advances that timeline on its own rock-steady clock. We
//  keep a small ROLLING WINDOW of upcoming ticks scheduled; each tick's
//  completion schedules one more, so the queue never runs dry. Even a MUTED tick
//  must keep the window turning — see `scheduleNextTick` for how we handle the
//  "no buffer to hang a completion on" case.
//
//  CONFIGURATION CONTRACT (matches `bpm`'s existing one):
//  All config (`bpm`, `beatsPerBar`, `subdivision`, `accents`, `soundSet`,
//  haptics) is read at `start()`. The view model changes config then RESTARTS
//  the engine to make it audible immediately — same pattern as tempo today.
//

import AVFoundation
import Observation

@MainActor
@Observable
final class MetronomeEngine {

    // MARK: Public configuration (applied on the next `start()`)

    /// Tempo in beats per minute.
    var bpm: Double = 120

    /// How many beats make up one bar. The accents array is expected to be this
    /// long; ticks repeat every `beatsPerBar` beats. Defaults to 4 (4/4).
    var beatsPerBar: Int = 4

    /// How finely each beat is subdivided. `.quarter` (1 tick/beat) means clicks
    /// land only on beats; finer subdivisions add in-between ticks.
    var subdivision: Subdivision = .quarter

    /// The per-beat emphasis, one entry per beat in the bar (index 0 = the
    /// downbeat). If this is shorter than `beatsPerBar` we treat missing beats as
    /// `.normal`; the view model keeps it sized correctly.
    var accents: [BeatAccent] = [.accent, .normal, .normal, .normal]

    /// The click timbre. Picks the accent / normal / subdivision sounds.
    var soundSet: MetronomeSoundSet = .classic

    /// Whether to fire a per-BEAT haptic. Independent of sound, so "everything
    /// muted + haptics on" = silent practice (feel + the visual ring only).
    var hapticsEnabled = false

    /// Whether the click is currently running.
    private(set) var isPlaying = false

    // MARK: Audio machinery (plumbing, not observed)

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var isSetUp = false
    @ObservationIgnored private var sampleRate: Double = 44_100
    @ObservationIgnored private var audioFormat: AVAudioFormat?

    /// The three role buffers for the CURRENT sound set, rebuilt at each
    /// `start()` (so a sound-set change is picked up on restart). Kept around so
    /// we don't re-synthesize on every tick.
    @ObservationIgnored private var accentBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var normalBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var subdivisionBuffer: AVAudioPCMBuffer?

    /// A SILENT buffer (zeros), the same length as a click, scheduled in place of
    /// a muted beat. Scheduling silence — rather than scheduling nothing — means
    /// EVERY tick has a real buffer with a `.dataPlayedBack` completion. That in
    /// turn lets us (a) keep the rolling window turning uniformly and (b) fire the
    /// per-beat haptic from the completion (i.e. when the beat actually PLAYS),
    /// which is what makes silent practice's buzz land on time.
    @ObservationIgnored private var silentBuffer: AVAudioPCMBuffer?

    /// How many ticks we keep scheduled ahead of "now." A small cushion so the
    /// queue never empties between a tick finishing and the next being scheduled.
    @ObservationIgnored private let scheduleWindow = 8

    /// The index of the next TICK we still need to schedule. Advances as ticks
    /// play and we top the window up. (Was `nextBeatToSchedule` pre-#16.)
    @ObservationIgnored private var nextTickToSchedule = 0

    /// The subdivision in effect for THIS run, captured at `start()` so a mid-run
    /// config change can't desync the tick math from what's actually scheduled.
    @ObservationIgnored private var ticksPerBeat = 1

    /// Optional per-beat haptic. Created lazily the first time haptics are on, so
    /// we don't allocate a Taptic generator for users who never enable them.
    @ObservationIgnored private var haptics: MetronomeHaptics?

    init() {}

    // MARK: Lifecycle

    /// Start the click from tick 0 (an immediate downbeat) using the current
    /// configuration.
    func start() {
        guard !isPlaying else { return }
        do {
            try setUpIfNeeded()
        } catch {
            // If the playback graph can't start there's nothing to click. Fail
            // quietly; a future face can surface an error.
            return
        }

        // Snapshot the config that affects scheduling for this whole run, so the
        // completion callbacks (which fire on audio threads, later) read a stable
        // picture rather than a value the UI might be mutating.
        ticksPerBeat = max(subdivision.ticksPerBeat, 1)

        // Rebuild the role buffers for the selected sound set / format.
        rebuildBuffers()

        // Warm up haptics if they're on for this run.
        if hapticsEnabled {
            let h = haptics ?? MetronomeHaptics()
            haptics = h
            h.prepare()
        }

        nextTickToSchedule = 0
        isPlaying = true

        // Pre-schedule the initial window, then start the node. (Tick 0's sample
        // offset is 0, so the downbeat sounds the instant playback begins.)
        for _ in 0..<scheduleWindow {
            scheduleNextTick()
        }
        player.play()
    }

    /// Stop the click and clear anything still queued.
    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        player.stop()
        // `stop()` already flushes scheduled buffers; reset our bookkeeping so the
        // next start begins cleanly at tick 0.
        nextTickToSchedule = 0
    }

    /// Fully tear down the audio graph (e.g. when leaving the Metronome tool).
    func shutdown() {
        stop()
        if isSetUp {
            engine.stop()
            isSetUp = false
        }
    }

    // MARK: Setup & buffers

    /// Build the audio graph once. Buffers are (re)built per-start in
    /// `rebuildBuffers()` so a sound-set change is honored on restart.
    private func setUpIfNeeded() throws {
        guard !isSetUp else {
            // Engine exists but may have been stopped by a previous shutdown.
            if !engine.isRunning { try engine.start() }
            return
        }

        // The format we'll synthesize and connect in — the output's own format.
        let format = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        audioFormat = format

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        engine.prepare()
        try engine.start()
        isSetUp = true
    }

    /// Synthesize the three role buffers for the current `soundSet`. Cheap, and
    /// only done once per start, so re-creating on a config-change restart is
    /// fine.
    private func rebuildBuffers() {
        guard let format = audioFormat else { return }
        accentBuffer = soundSet.buffer(for: .accent, format: format)
        normalBuffer = soundSet.buffer(for: .normal, format: format)
        subdivisionBuffer = soundSet.buffer(for: .subdivision, format: format)

        // A silent buffer the same length as a click, used for muted beats. We
        // size it from a real click's sample count so its `.dataPlayedBack`
        // completion lands at the same point a normal click's would.
        let clickCount = accentBuffer.map { Int($0.frameLength) }
            ?? Int(format.sampleRate * 0.03)
        silentBuffer = ClickSound.buffer(format: format,
                                         samples: [Float](repeating: 0, count: max(1, clickCount)))
    }

    // MARK: Scheduling

    /// The `BeatAccent` for a beat index, wrapping around the bar and tolerating
    /// a short/empty `accents` array (missing beats default to `.normal`).
    private func accent(forBeat beat: Int) -> BeatAccent {
        guard beatsPerBar > 0, !accents.isEmpty else { return .normal }
        let indexInBar = beat % beatsPerBar
        // Guard against an `accents` array shorter than `beatsPerBar`.
        guard indexInBar < accents.count else { return .normal }
        return accents[indexInBar]
    }

    /// Pick the buffer to play for tick `tick` (or `nil` to play nothing). Also
    /// reports whether this tick is a BEAT and, if so, its accent — the engine
    /// uses that to fire the per-beat haptic.
    private func plan(forTick tick: Int) -> (buffer: AVAudioPCMBuffer?, isBeat: Bool, accent: BeatAccent) {
        // A tick lands on a beat when it's an exact multiple of ticksPerBeat.
        let isBeat = (tick % ticksPerBeat == 0)
        guard isBeat else {
            // Between-beats: the quiet subdivision click.
            return (subdivisionBuffer, false, .normal)
        }
        // On a beat: choose by its accent. `.muted` → no buffer (but still a beat,
        // so the haptic can still fire for silent practice).
        let beat = tick / ticksPerBeat
        let a = accent(forBeat: beat)
        switch a {
        case .accent: return (accentBuffer, true, .accent)
        case .normal: return (normalBuffer, true, .normal)
        // Muted → schedule SILENCE (not nothing), so the tick still has a
        // completion to fire the haptic + refill the window on time.
        case .muted:  return (silentBuffer, true, .muted)
        }
    }

    /// Schedule tick `nextTickToSchedule` at its exact sample time, then advance.
    ///
    /// SUBDIVISIONS: the offset comes from `tickOffset(...)` (finer than beats),
    /// and which buffer we use depends on whether the tick is a beat (and, for a
    /// beat, its accent — muted uses the silent buffer).
    ///
    /// HAPTIC TIMING: we fire the per-beat haptic from the buffer's PLAYBACK
    /// completion (`.dataPlayedBack`), NOT at schedule-time. Schedule-time would
    /// fire it up to a whole `scheduleWindow` of ticks early (a burst at start,
    /// then a steady but audio-misaligned lead). Firing on completion makes the
    /// buzz land with the click — including for muted beats, which now schedule
    /// silence so they still get a completion. That's what keeps silent practice
    /// honest. (`.muted` beats buzz at normal strength; only the accent gets the
    /// stronger tap.)
    private func scheduleNextTick() {
        let tick = nextTickToSchedule
        nextTickToSchedule += 1

        let plan = plan(forTick: tick)
        let isBeat = plan.isBeat
        let accented = plan.accent == .accent

        // The drift-free sample offset of this tick (anchored to tick 0).
        let offset = MetronomeSequencer.tickOffset(ofTick: tick, bpm: bpm,
                                                    sampleRate: sampleRate,
                                                    ticksPerBeat: ticksPerBeat)
        let when = AVAudioTime(sampleTime: AVAudioFramePosition(offset), atRate: sampleRate)

        guard let buffer = plan.buffer else {
            // Safety net: if (rarely) a buffer failed to synthesize, keep the
            // window turning so the click doesn't stall. We still buzz the beat so
            // silent practice keeps its pulse.
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                if self.hapticsEnabled, isBeat { self.haptics?.beat(accented: accented) }
                self.scheduleNextTick()
            }
            return
        }

        player.scheduleBuffer(buffer, at: when, options: [],
                              completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // Fires on an audio thread once this tick has PLAYED. Hop to the main
            // actor, buzz on beats (so the haptic lands with the sound), and queue
            // one more tick to refill the window.
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                if self.hapticsEnabled, isBeat { self.haptics?.beat(accented: accented) }
                self.scheduleNextTick()
            }
        }
    }
}
