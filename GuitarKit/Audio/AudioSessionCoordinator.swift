//
//  AudioSessionCoordinator.swift
//  GuitarKit
//
//  The ONE owner of the app's `AVAudioSession` — the single place that decides
//  how the shared session is configured, from what every part of the app
//  currently needs.
//
//  WHY ONE OWNER?
//  iOS has ONE audio session per app (`AVAudioSession.sharedInstance()`). Its
//  "category" declares intent: `.playAndRecord` (mic + speaker) or `.playback`
//  (speaker only). Several tools use audio, often at the same time — the
//  Tuner listens to the mic while the Metronome keeps clicking from its
//  mini-player; Chords and Scales play notes. If each configured the session
//  on its own, they'd stomp on each other: e.g. stopping the metronome used to
//  DEACTIVATE the whole session, killing the Tuner's mic mid-listen.
//
//  HOW IT DECIDES:
//  Each user of audio holds a `Client` and states what it needs right now —
//  recording, playback, or nothing. The coordinator derives the session from
//  ALL current needs:
//
//      recording, nothing playing → play-and-record, MEASUREMENT mode: iOS
//                                   skips its own mic processing, so the
//                                   pitch detector hears the raw string
//      recording AND playback     → play-and-record, DEFAULT mode: measurement
//                                   mode also skips the speaker's loudness
//                                   processing, which made a running metronome
//                                   noticeably quieter
//      playback only              → playback (full speaker loudness)
//      nobody needs audio         → deactivate (other apps' audio comes back)
//
//  and touches iOS only when that result CHANGES — repeated requests are free.
//  A switch can make iOS reconfigure running audio engines; each engine
//  recovers on its own (`AVAudioEngineConfigurationChange`).
//

import AVFoundation

/// The audio-session seam one part of the app talks to: state what it needs,
/// or release. Behind a protocol so the `TunerCoordinator` can be unit-tested
/// with a fake that just records which configuration was requested.
@MainActor
protocol AudioSessionConfiguring: AnyObject {
    /// "I'm capturing the mic now."
    func configureForRecording() throws
    /// "I'm producing sound now (and not using the mic)."
    func configureForPlayback() throws
    /// "I don't need audio any more." (The session itself is only deactivated
    /// once NOBODY needs it.)
    func deactivate()
}

@MainActor
final class AudioSessionCoordinator {

    /// The app-wide instance — there is one audio session, so one owner.
    static let shared = AudioSessionCoordinator()

    nonisolated enum Need { case recording, playback }

    /// How the session is configured (nil = inactive).
    nonisolated enum Configuration {
        /// Mic + speaker, no OS processing: the cleanest input for pitch detection.
        case measuring
        /// Mic + speaker with normal processing: something is also playing.
        case playAndRecord
        /// Speaker only.
        case playback
    }

    private let session = AVAudioSession.sharedInstance()
    private var needs: [ObjectIdentifier: Need] = [:]
    private var applied: Configuration?

    private init() {}

    /// A handle for one user of audio (the Tuner, the Metronome, a tool's
    /// note player). Its needs are tracked separately from everyone else's.
    func client() -> Client { Client(owner: self) }

    /// One user of audio's view of the coordinator.
    final class Client: AudioSessionConfiguring {
        private let owner: AudioSessionCoordinator
        fileprivate init(owner: AudioSessionCoordinator) { self.owner = owner }

        func configureForRecording() throws { try owner.set(.recording, for: self) }
        func configureForPlayback() throws { try owner.set(.playback, for: self) }
        func deactivate() { try? owner.set(nil, for: self) }
    }

    // MARK: Policy

    private func set(_ need: Need?, for client: Client) throws {
        needs[ObjectIdentifier(client)] = need
        try apply()
    }

    /// THE POLICY, as a pure function: the configuration every current need
    /// calls for.
    nonisolated static func configuration(for needs: [Need]) -> Configuration? {
        switch (needs.contains(.recording), needs.contains(.playback)) {
        case (true, false):  return .measuring
        case (true, true):   return .playAndRecord
        case (false, true):  return .playback
        case (false, false): return nil
        }
    }

    /// Apply the policy; touch iOS only when the result changes.
    private func apply() throws {
        let wanted = Self.configuration(for: Array(needs.values))
        guard wanted != applied else { return }

        switch wanted {
        case .measuring, .playAndRecord:
            // .measurement turns off the OS's automatic gain/EQ so the pitch
            // detector hears the raw string — but it also skips the speaker's
            // loudness processing, so it's only used when nothing else plays.
            // .defaultToSpeaker sends output to the speaker, not the earpiece;
            // .duckOthers politely lowers other apps' audio while we listen.
            try session.setCategory(.playAndRecord,
                                    mode: wanted == .measuring ? .measurement : .default,
                                    options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
        case .playback:
            // .playback is audible even with the silent switch on — what you
            // want for "tap to hear the note" and for a metronome.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        case nil:
            // Nobody needs audio: release it so other apps' audio resumes.
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
        applied = wanted
    }
}
