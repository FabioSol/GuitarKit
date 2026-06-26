//
//  AudioSessionCoordinator.swift
//  GuitarKit
//
//  The single owner of the app's `AVAudioSession` POLICY — i.e. the one place
//  that decides "are we recording (mic) or playing back (speaker) right now?"
//
//  WHY DOES THIS NEED TO EXIST AT ALL?
//  iOS has ONE shared audio session per app (`AVAudioSession.sharedInstance()`)
//  that arbitrates audio across the whole system. Its "category" declares your
//  intent: `.record` means "I capture input", `.playback` means "I produce
//  output". The Tuner does BOTH at different moments — it listens to the mic to
//  detect pitch, but when you tap a peg in tone-mode it must instead PLAY a tone
//  out the speaker. You can't sensibly do both at once here (and we don't want
//  the tuner to hear its own tone), so we flip the session between modes.
//
//  Today both `AudioInputEngine` (in `start()`) and a tone playback path want to
//  set the category. If each sets it independently they can stomp on each other.
//  Centralizing the category switches HERE — behind a thin, well-documented
//  wrapper the orchestrator calls — keeps that policy in one obvious place. (See
//  the integration notes for the planned ownership cleanup.)
//
//  THE PRD CONTRACT (~line 121): "AudioSession coordinator owns record↔playback
//  category switching and tears down the mic when leaving the Tuner."
//

import AVFoundation

/// The audio-session seam: switch the shared session between record and playback,
/// or release it. Behind a protocol so the `TunerCoordinator` can be unit-tested
/// with a fake that just records which configuration was requested — no real
/// `AVAudioSession`.
@MainActor
protocol AudioSessionConfiguring: AnyObject {
    func configureForRecording() throws
    func configureForPlayback() throws
    func deactivate()
}

/// Owns `AVAudioSession` category/mode switching for the Tuner.
///
/// `@MainActor` because session changes are driven by UI events (entering the
/// Tuner, tapping a peg, leaving) and should happen on one predictable thread.
/// It's a thin wrapper: it holds no audio of its own, it just configures the
/// shared session. A `final class` (reference type) because it represents one
/// shared piece of system state — value-copy semantics would be wrong.
@MainActor
final class AudioSessionCoordinator: AudioSessionConfiguring {

    /// The process-wide shared session every app talks to. Stored once so each
    /// method reads clearly. `private` — callers go through our methods.
    private let session = AVAudioSession.sharedInstance()

    init() {}

    // MARK: - Recording (mic / pitch detection)

    /// Configure the session for RECORDING — the mode pitch detection wants.
    ///
    /// The orchestrator calls this when the Tuner is detecting pitch, and again
    /// after a tone finishes (to hand the mic back). The category/mode here match
    /// exactly what `AudioInputEngine.start()` expects:
    ///   • `.playAndRecord` — we capture input AND can produce output simultaneously,
    ///                        so background audio (e.g. the metronome) keeps playing
    ///                        while the tuner listens.
    ///   • `.measurement`   — disables most of the OS's automatic gain/EQ so the
    ///                        detector sees a clean signal (a tuner wants raw).
    ///   • `.defaultToSpeaker` — routes output to the speaker, not the earpiece.
    ///   • `.duckOthers`    — politely lowers other apps' audio if any.
    ///
    /// - Throws: if the OS refuses the category change (e.g. another app holds
    ///   the mic). The caller decides how to surface that.
    func configureForRecording() throws {
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true)
    }

    // MARK: - Playback (tone generator)

    /// Configure the session for PLAYBACK — so a tapped peg's tone is audible.
    ///
    /// The orchestrator calls this RIGHT BEFORE playing a tone, and pairs it with
    /// pausing detection (stopping the mic) so the tuner doesn't hear itself.
    ///   • `.playback`     — we produce output. Crucially, this category plays
    ///                       through the speaker EVEN WHEN THE SILENT/RING switch
    ///                       is on, which is what you want for a "tap to hear the
    ///                       note" feature (a `.record`/ambient session would be
    ///                       silenced by the hardware switch).
    ///   • `.default` mode — no special processing needed for clean synth output.
    ///   • `.mixWithOthers`— let the tone coexist with other audio rather than
    ///                       forcibly interrupting it; tweak if you'd rather duck.
    ///
    /// - Throws: if the OS refuses the category change.
    func configureForPlayback() throws {
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    // MARK: - Teardown (leaving the Tuner)

    /// Deactivate the session entirely — the "tear down when leaving the Tuner"
    /// half of the PRD contract. After the mic engine and tone engine have both
    /// stopped, this releases the session so OTHER apps can resume normal audio
    /// (and the mic indicator turns off).
    ///
    /// `notifyOthersOnDeactivation` is the polite flag that tells previously
    /// interrupted/ducked apps "you can come back now." We swallow any throw with
    /// `try?` because a failed deactivation is non-fatal cleanup — exactly how
    /// `AudioInputEngine.stop()` treats it.
    func deactivate() {
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
