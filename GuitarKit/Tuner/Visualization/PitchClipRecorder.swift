//
//  PitchClipRecorder.swift
//  GuitarKit
//
//  DEVELOPER-ONLY: records labelled clips of the RAW samples the live pitch
//  tracker sees, so real guitar plucks can be replayed in the benchmark
//  (`GuitarKitTests/Pitch/Benchmark`) instead of guessing from synthetic
//  signals. Compiled out of release builds, like the rest of the Tuner Lab.
//
//  WHAT A CLIP IS:
//  Two files with the same base name in Documents/PitchClips/:
//    • `<name>.wav`  — mono 32-bit float, at the hardware sample rate, exactly
//                      the windows `PitchDetector.process` received, in order.
//    • `<name>.json` — the label (which note was plucked, how hard, what noise
//                      was in the room) plus the context needed to replay it
//                      faithfully (detection band, reference pitch, the window
//                      size the device delivered).
//
//  Clips are fixed-length: press Record, pluck once, and it stops by itself.
//  Same length every time keeps clips comparable.
//

#if DEBUG
import AVFoundation
import Observation

@MainActor
@Observable
final class PitchClipRecorder {

    // MARK: Labels

    /// How hard the string was plucked.
    enum Pluck: String, CaseIterable, Codable {
        case soft, medium, hard
    }

    /// What else was audible in the room — the same kinds of interference
    /// the benchmark generates (see `Interference` in the test target), so
    /// real and generated clips can be compared row by row.
    enum Background: String, CaseIterable, Codable {
        case quiet
        case fan            // steady noise: fan, AC, traffic rumble
        case instruments    // someone else playing (music class)
        case talking        // voices in the room
        case clicks         // typing, tapping, things being set down
        case video          // a phone / TV playing video (speech + music)
        case other
    }

    /// Everything written to a clip's `.json` sidecar. The benchmark decodes
    /// this same shape, so change it only together with `RecordedClip` in the
    /// test target (and bump `version`).
    struct Metadata: Codable, Equatable {
        var version = 2
        /// The plucked note's name ("E2"), or `nil` for a noise-only clip.
        var note: String?
        /// The target frequency the string should sound at (capo-shifted, at
        /// `referenceA`), or `nil` for a noise-only clip.
        var expectedHz: Double?
        var pluck: Pluck?
        var background: Background
        var instrument: String
        var tuning: String
        var referenceA: Double
        /// The detection band in force while recording.
        var bandMinHz: Double
        var bandMaxHz: Double
        var highPassHz: Double
        var lowPassHz: Double
        /// The tuning's string targets (Hz, capo-shifted) — empty if recorded
        /// in chromatic mode. (Added in version 2.)
        var targetsHz: [Double] = []
        /// Filled in by the recorder.
        var sampleRate: Double = 0
        var windowFrames: Int = 0
        var durationSeconds: Double = 0
        var recordedAt = Date()
    }

    // MARK: Observable state (drives the Lab panel)

    private(set) var isRecording = false
    /// Seconds captured so far in the current clip.
    private(set) var elapsed: Double = 0
    /// Saved clips (the `.wav` files), newest first.
    private(set) var clips: [URL] = []
    /// The last save/write problem, shown in the panel.
    private(set) var lastError: String?

    /// How long each clip records for.
    var clipSeconds: Double = 6

    // MARK: Capture buffer

    @ObservationIgnored private var pending: Metadata?
    @ObservationIgnored private var samples: [Float] = []

    init() {
        refreshClips()
    }

    /// Where clips live: Documents/PitchClips/.
    static var directory: URL {
        URL.documentsDirectory.appending(path: "PitchClips", directoryHint: .isDirectory)
    }

    // MARK: Recording

    /// Start a new clip. Samples arrive through `append` until `clipSeconds`
    /// worth is captured, then the clip saves itself.
    func start(_ metadata: Metadata) {
        pending = metadata
        samples.removeAll(keepingCapacity: true)
        elapsed = 0
        lastError = nil
        isRecording = true
    }

    /// Abandon the current clip without saving.
    func cancel() {
        pending = nil
        samples.removeAll()
        isRecording = false
        elapsed = 0
    }

    /// Called by `PitchDetector` with every window it processes.
    func append(_ window: [Float], sampleRate: Double) {
        guard isRecording, var metadata = pending, sampleRate > 0 else { return }
        if metadata.sampleRate == 0 {
            metadata.sampleRate = sampleRate
            metadata.windowFrames = window.count
            pending = metadata
        }
        samples.append(contentsOf: window)
        elapsed = Double(samples.count) / sampleRate
        if elapsed >= clipSeconds { finish() }
    }

    private func finish() {
        guard var metadata = pending else { return }
        isRecording = false
        pending = nil
        metadata.durationSeconds = elapsed
        do {
            try Self.write(samples, metadata: metadata)
        } catch {
            lastError = "Couldn't save clip: \(error.localizedDescription)"
        }
        samples.removeAll()
        refreshClips()
    }

    // MARK: Files

    func delete(_ clip: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: clip)
        try? fm.removeItem(at: clip.deletingPathExtension().appendingPathExtension("json"))
        refreshClips()
    }

    /// Every file of every clip (`.wav` + `.json`), for sharing.
    var allFiles: [URL] {
        clips.flatMap { [$0, $0.deletingPathExtension().appendingPathExtension("json")] }
    }

    private func refreshClips() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        // Names start with a sortable timestamp, so newest-first is a reverse sort.
        clips = urls.filter { $0.pathExtension == "wav" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// A readable, sortable, filesystem-safe base name, e.g.
    /// `20261010-153012_E2_soft_quiet`.
    static func baseName(for metadata: Metadata) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: metadata.recordedAt)
        let note = (metadata.note ?? "noise").replacingOccurrences(of: "#", with: "s")
        let pluck = metadata.pluck.map { "_\($0.rawValue)" } ?? ""
        return "\(stamp)_\(note)\(pluck)_\(metadata.background.rawValue)"
    }

    private static func write(_ samples: [Float], metadata: Metadata) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = directory.appending(path: baseName(for: metadata))

        // WAV: mono Float32 — lossless, and `AVAudioFile` reads it straight
        // back into the same `[Float]` the tracker saw.
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: metadata.sampleRate,
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            channel.update(from: src.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: base.appendingPathExtension("wav"),
                                   settings: format.settings,
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        try file.write(from: buffer)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: base.appendingPathExtension("json"))
    }
}
#endif
