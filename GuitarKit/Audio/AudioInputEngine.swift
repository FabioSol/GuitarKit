//
//  AudioInputEngine.swift
//  GuitarKit
//
//  The thin wrapper around the microphone. It opens `AVAudioEngine`, taps the
//  input, and exposes:
//    • a smoothed input LEVEL (0...1) to drive this slice's meter, and
//    • the raw audio BUFFERS, so slice #03's pitch detector can consume the
//      exact same stream without us re-plumbing the hardware.
//
//  WHY A PROTOCOL IN FRONT OF IT?
//  Pitch detection (next slice) wants buffers, the tuner UI wants a level, and
//  tests/previews want neither real microphone. Defining `AudioInputProviding`
//  lets all of those depend on a small *interface* instead of this concrete,
//  hardware-bound class — so a fake/synthetic feed can stand in later. This is
//  the "wrap the hardware/realtime boundary thin" principle from the PRD.
//

import AVFoundation
import Observation

// MARK: - The seam: a protocol consumers depend on

/// What any audio *source* must provide, real microphone or synthetic feed.
///
/// `AnyObject` constrains conformers to be classes (reference types). We want
/// that here because an audio engine is inherently a single, shared, mutable
/// piece of stateful hardware — value-type copy semantics would be wrong.
/// `@MainActor` keeps the published `level` safe to read from SwiftUI.
@MainActor
protocol AudioInputProviding: AnyObject {

    /// The latest smoothed input level, `0` (silence) … `1` (loud). Views bind
    /// to this to animate a meter. It's read-only to consumers (`get`).
    var level: Float { get }

    /// Start capturing from the source. May throw if the audio session or
    /// engine fails to start (e.g. another app holds the mic).
    func start() throws

    /// Stop capturing and release the tap, so the mic light turns off when we
    /// leave the Tuner.
    func stop()

    /// Register a sink for raw audio buffers — this is the hook slice #03's
    /// pitch detector will use. We pass the buffer plus its format so the
    /// consumer knows the sample rate/channel layout. The closure may be called
    /// on a high-priority audio thread, so consumers must keep it light.
    func onBuffer(_ handler: @escaping (AVAudioPCMBuffer) -> Void)
}

// MARK: - The real, microphone-backed implementation

/// Concrete `AudioInputProviding` driven by `AVAudioEngine`'s input node.
///
/// `@Observable` so SwiftUI re-renders when `level` updates; `@MainActor`
/// because that published state and the SwiftUI binding live on the main
/// thread. The actual audio callback fires on an audio thread — see `start()`
/// for how we hop back to the main actor before mutating `level`.
@MainActor
@Observable
final class AudioInputEngine: AudioInputProviding {

    // MARK: Published output

    /// Smoothed 0...1 level. `private(set)` → the engine writes it, the UI only
    /// reads it.
    private(set) var level: Float = 0

    // MARK: Private audio machinery
    //
    // These are excluded from observation because they're plumbing, not UI
    // state. `@ObservationIgnored` tells the `@Observable` macro "don't track
    // changes to this" — observing an `AVAudioEngine` would be meaningless and
    // wasteful.

    /// The engine that hosts our audio graph. `inputNode` below is its mic.
    @ObservationIgnored private let engine = AVAudioEngine()

    /// Whether we've installed a tap / started — guards against double start or
    /// stop, which AVAudioEngine dislikes.
    @ObservationIgnored private var isRunning = false

    /// Optional downstream consumer of raw buffers (the future pitch detector).
    ///
    /// `nonisolated(unsafe)` because it is read from inside the audio tap, which
    /// runs on a real-time *audio thread*, NOT the main actor. We set it once
    /// (before `start()`) and only read it afterward, so there's no real data
    /// race — `unsafe` tells the compiler "I've reasoned about this, trust me."
    /// Without it, this `@MainActor` type couldn't legally touch the property
    /// from the audio thread.
    @ObservationIgnored nonisolated(unsafe) private var bufferHandler: ((AVAudioPCMBuffer) -> Void)?

    /// How many samples the tap hands us per callback. 4096 at 44.1 kHz ≈ 93 ms
    /// — a good balance: long enough for a stable RMS, short enough that the
    /// meter still feels live. (Pitch detection later may request its own size;
    /// the OS treats this as a hint.)
    @ObservationIgnored private let bufferSize: AVAudioFrameCount = 4096

    init() {}

    // MARK: Buffer subscription

    func onBuffer(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        bufferHandler = handler
    }

    // MARK: Lifecycle

    /// Configure the audio session for recording, install the input tap, and
    /// start the engine.
    ///
    /// STEP BY STEP:
    ///  1. Configure `AVAudioSession` — tell iOS we want to record. The
    ///     `.measurement` mode minimizes the OS's own signal processing
    ///     (AGC/filtering) so the pitch detector later sees a cleaner signal.
    ///  2. Grab `engine.inputNode` and its hardware format.
    ///  3. `installTap` — hand the OS a closure it calls repeatedly with fresh
    ///     buffers of microphone audio.
    ///  4. `engine.prepare()` then `engine.start()`.
    func start() throws {
        // Idempotent: starting an already-running engine would throw.
        guard !isRunning else { return }

        // 1) AUDIO SESSION. The shared session arbitrates audio across apps.
        let session = AVAudioSession.sharedInstance()
        // `.record` category = we capture input. `.measurement` mode disables
        // most of the OS's automatic gain/EQ so we get the raw signal a tuner
        // wants. `.duckOthers` politely lowers other apps' audio if any.
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)

        // 2) INPUT NODE + its native format (sample rate, channel count). We tap
        // in the hardware's own format to avoid surprise conversions.
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        // 3) INSTALL THE TAP. The closure runs on a real-time audio thread every
        // time `bufferSize` samples are ready. Keep it FAST and allocation-free
        // — heavy work or blocking here causes audio glitches.
        // NOTE ON THREADING: the tap closure runs on a real-time AUDIO thread,
        // not the main actor. This class is `@MainActor`, so the closure is
        // declared `nonisolated` and must NOT touch main-actor state directly.
        // We do all the heavy/raw work here off-main, then hop to the main actor
        // only to publish `level` (the one piece of UI-driving state).
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            // `[weak self]` avoids a retain cycle (the engine holds the closure;
            // the closure must not strongly hold the engine forever).
            guard let self else { return }

            // Hand the raw buffer to any downstream consumer (pitch detector).
            // `bufferHandler` is `nonisolated(unsafe)`, so reading it here is OK.
            // We call it on the audio thread on purpose: that consumer will do
            // its own real-time-safe processing.
            self.bufferHandler?(buffer)

            // Compute this buffer's level with the PURE math (no actor state
            // touched). `samples(from:)` copies the first channel into a `[Float]`.
            let raw = AudioLevel.meterValue(fromRMS: AudioLevel.rms(of: Self.samples(from: buffer)))

            // Publishing `level` touches main-actor UI state, so hop over with a
            // `Task { @MainActor in }`. The smoothing reads the *previous* level
            // on the main actor, keeping all `level` access on one thread.
            Task { @MainActor in
                self.level = AudioLevel.smooth(previous: self.level, target: raw)
            }
        }

        // 4) PREPARE + START the engine graph.
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }

        // Remove the tap first, then stop the engine — order matters so no
        // buffer arrives after teardown.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        // Decay the meter to zero so a stale level doesn't linger on screen.
        level = 0

        // Deactivate our session so other apps can resume normal audio. We
        // ignore the throw here because failing to deactivate is non-fatal.
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: Buffer → samples helper

    /// Copy the first channel of an `AVAudioPCMBuffer` into a plain `[Float]`
    /// that `AudioLevel`'s pure math can chew on.
    ///
    /// `AVAudioPCMBuffer.floatChannelData` is a C-style pointer-to-pointers:
    /// one pointer per channel, each pointing at that channel's raw samples. We
    /// take channel 0 (mono is enough for level + pitch) and read `frameLength`
    /// floats out of it. `static` because it needs nothing from `self`.
    static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        // `floatChannelData` is nil if the buffer isn't float PCM; bail safely.
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        // `channelData[0]` is an `UnsafePointer<Float>` to channel 0's samples.
        // `UnsafeBufferPointer` wraps it as a Swift collection of known length
        // so we can build a safe `Array` copy from it.
        let firstChannel = UnsafeBufferPointer(start: channelData[0], count: frameCount)
        return Array(firstChannel)
    }
}
