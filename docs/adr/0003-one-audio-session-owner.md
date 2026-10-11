# One owner for the audio session, configured from every tool's needs

iOS gives an app a single `AVAudioSession`, but several tools use audio at once (the Tuner's mic while the Metronome clicks from its mini-player; Chords and Scales playing notes). When each configured the session itself, they broke each other — stopping the metronome deactivated the session under the Tuner's live mic. Now `AudioSessionCoordinator.shared` is the only code that touches the session: each tool holds a client and states what it needs (recording, playback, nothing), and the session is derived from all needs together.

## Consequences

- Leaving the Tuner while the metronome plays keeps the session in play-and-record rather than switching to playback, because reconfiguring would disturb the metronome's running engine. This looks like a leftover mic configuration; it is deliberate.
- The session is deactivated only when no tool needs audio.
- `AudioInputEngine` never configures the session; whoever starts it states "recording" first.
