//
//  PitchDetector.swift
//  GuitarKit
//
//  The LIVE, observable pitch detector that the Tuner UI binds to. It is a thin
//  adapter: all of the actual pitch logic lives in the pure `PitchTracker`.
//  This class only does what a pure value can't:
//
//    • run the tracker OFF the main thread, fed straight from the mic, and
//    • publish the result as observable state for SwiftUI (`reading`).
//
//  THREADS:
//
//      audio thread ──copy samples──▶ worker queue (PitchTracker) ──reading──▶ main actor
//
//  Detection costs a few milliseconds per ~0.1 s window — far more in an
//  unoptimized Debug build — and the main thread also has to draw the UI. So
//  the tracker lives on its own serial queue; only the finished reading hops
//  to the main actor. If the queue ever falls behind (a slow Debug build), new
//  windows are DROPPED rather than queued, so readings never lag further and
//  further behind the strings.
//
//  WHY A PROTOCOL IN FRONT OF IT (`PitchDetecting`)?
//  The `TunerCoordinator` and its tests depend on this small interface, not the
//  concrete class, so tests can pass a fake that just records what it was told.
//

import AVFoundation
import Observation

// MARK: - The seam

/// What any pitch detector exposes. Class-bound + `@MainActor` because `reading`
/// is observable UI state read on the main thread.
@MainActor
protocol PitchDetecting: AnyObject {
    /// The latest reading, or `nil` when nothing confident is detected.
    var reading: PitchReading? { get }

    /// Called on the main actor with every new reading (including `nil`), so
    /// the coordinator can feed the tuning session without a view in between.
    var onReading: ((PitchReading?) -> Void)? { get set }

    /// How detection behaves: the tuning-derived band, the reference pitch,
    /// and the Tuner Lab knobs. Re-assigning an unchanged value is a no-op, so
    /// the coordinator can re-apply it on every tuning/mode transition.
    var config: PitchTrackerConfig { get set }

    /// Subscribe to a live audio source's buffer stream (wires the mic into
    /// detection). Re-attaching just replaces the previous subscription.
    func attach(to source: AudioInputProviding)

    /// Drop transient state (smoothing history) — call when audio stops.
    func reset()
}

// MARK: - The live implementation

/// Runs `PitchTracker` on a background queue and publishes its readings.
///
/// `@Observable` so SwiftUI re-renders when `reading` changes; `@MainActor`
/// because that published state lives on the main thread.
@MainActor
@Observable
final class PitchDetector: PitchDetecting {

    /// The current reading, written on the main actor and read by the UI.
    private(set) var reading: PitchReading?

    @ObservationIgnored var onReading: ((PitchReading?) -> Void)?

    /// The configuration, mirrored here so reads are instant on the main
    /// actor; every write is forwarded to the worker (in order with the audio).
    @ObservationIgnored var config: PitchTrackerConfig {
        didSet { if config != oldValue { worker.setConfig(config) } }
    }

    /// Owns the tracker and its queue.
    @ObservationIgnored private let worker: Worker

    /// Bumped on every `reset()`. Results computed before a reset carry the old
    /// number and are dropped instead of resurrecting a stale reading.
    @ObservationIgnored private var generation = 0

    #if DEBUG
    /// Tuner Lab clip recorder: when set, every window of raw samples the
    /// tracker sees is also handed to it, so a recording replays EXACTLY what
    /// the live tuner processed.
    @ObservationIgnored var clipRecorder: PitchClipRecorder?
    #endif

    init(config: PitchTrackerConfig = PitchTrackerConfig()) {
        self.config = config
        worker = Worker(config: config)
    }

    /// Process one window SYNCHRONOUSLY and publish the result — the
    /// hardware-free entry point tests drive (the live path is `attach`).
    func process(samples: [Float], sampleRate: Double) {
        let (result, stamp) = worker.processNow(samples, sampleRate: sampleRate)
        publish(result, samples: samples, sampleRate: sampleRate, generation: stamp)
    }

    func reset() {
        generation += 1
        worker.reset(generation: generation)
        publish(nil, samples: nil, sampleRate: 0, generation: generation)
    }

    // MARK: Live wiring

    /// Subscribe this detector to a live audio source. Each hardware buffer is
    /// copied out on the audio thread and handed to the worker queue; the
    /// reading comes back to the main actor.
    func attach(to source: AudioInputProviding) {
        let worker = self.worker
        source.onBuffer { [weak self] buffer in
            // On the audio thread: copy the samples (the buffer is reused).
            let sampleRate = buffer.format.sampleRate
            let samples = AudioInputEngine.samples(from: buffer)
            worker.process(samples, sampleRate: sampleRate) { result, stamp in
                // On the worker queue: hop to the main actor to publish.
                Task { @MainActor in
                    self?.publish(result, samples: samples, sampleRate: sampleRate, generation: stamp)
                }
            }
        }
    }

    private func publish(_ result: PitchReading?, samples: [Float]?, sampleRate: Double, generation stamp: Int) {
        guard stamp == generation else { return }    // computed before a reset
        #if DEBUG
        if let samples { clipRecorder?.append(samples, sampleRate: sampleRate) }
        #endif
        if result != reading { reading = result }
        onReading?(result)
    }
}

// MARK: - The worker

extension PitchDetector {

    /// The tracker and the serial queue it lives on. Every access to `tracker`
    /// and `generation` happens on `queue` — that is the whole thread-safety
    /// story, which is why `@unchecked Sendable` is honest here.
    nonisolated final class Worker: @unchecked Sendable {
        private let queue = DispatchQueue(label: "GuitarKit.PitchDetector", qos: .userInitiated)
        private var tracker: PitchTracker
        private var generation = 0

        /// Windows waiting on the queue. Read/written under `pendingLock`
        /// because the audio thread increments it.
        private var pending = 0
        private let pendingLock = NSLock()
        /// More than this many windows waiting means we're falling behind.
        private static let maxPending = 2

        init(config: PitchTrackerConfig) {
            tracker = PitchTracker(config: config)
        }

        /// Queue one window (from the audio thread). Dropped if the queue is
        /// already behind. `completion` runs on the worker queue.
        func process(_ samples: [Float], sampleRate: Double,
                     completion: @escaping @Sendable (PitchReading?, Int) -> Void) {
            pendingLock.lock()
            guard pending < Self.maxPending else { pendingLock.unlock(); return }
            pending += 1
            pendingLock.unlock()

            queue.async {
                let result = self.tracker.process(samples: samples, sampleRate: sampleRate)
                let stamp = self.generation
                self.pendingLock.lock(); self.pending -= 1; self.pendingLock.unlock()
                completion(result, stamp)
            }
        }

        /// Process one window and wait for the answer (tests).
        func processNow(_ samples: [Float], sampleRate: Double) -> (PitchReading?, Int) {
            queue.sync { (tracker.process(samples: samples, sampleRate: sampleRate), generation) }
        }

        func setConfig(_ config: PitchTrackerConfig) {
            queue.async { self.tracker.config = config }
        }

        func reset(generation: Int) {
            queue.async {
                self.tracker.reset()
                self.generation = generation
            }
        }
    }
}
