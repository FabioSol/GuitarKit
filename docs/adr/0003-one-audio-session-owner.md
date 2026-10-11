# One owner for the audio session, configured from every tool's needs

iOS gives an app a single `AVAudioSession`, but several tools use audio at once (the Tuner's mic while the Metronome clicks from its mini-player; Chords and Scales playing notes). When each configured the session itself, they broke each other — stopping the metronome deactivated the session under the Tuner's live mic. Now `AudioSessionCoordinator.shared` is the only code that touches the session: each tool holds a client and states what it needs (recording, playback, nothing), and the session is derived from all needs together.

## Consequences

- The Tuner listens in *measurement* mode (no OS processing, the cleanest input for pitch detection) only while nothing else plays: measurement mode also skips the speaker's loudness processing, which made a running metronome noticeably quieter. With both, the session uses play-and-record's default mode; when the Tuner stops listening it returns to playback.
- Switching modes can make iOS reconfigure running audio engines, so each engine recovers on its own (`AVAudioEngineConfigurationChange`).
- The session is deactivated only when no tool needs audio.
- `AudioInputEngine` never configures the session; whoever starts it states "recording" first.
