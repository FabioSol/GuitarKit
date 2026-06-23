# 13 — Tone generator + AudioSession coordinator

> Type: AFK · Source: docs/PRD.md · Stories: 33, 34, 35

## What to build

An AudioSession coordinator that arbitrates between recording (mic) and playback (output) and tears the mic down when leaving the Tuner. On top of it, a headstock tone-mode toggle: tapping a peg plays that string's target pitch (a harmonic-rich oscillator for v1; Karplus–Strong plucked-string behind a feature flag). Playback sustains until tapped again (toggle), and detection pauses while a tone plays so the app doesn't hear itself.

## Acceptance criteria

- [ ] Tone-mode toggle: tapping a peg plays its target pitch and sustains until tapped again
- [ ] Detection pauses during playback and resumes afterward
- [ ] The AudioSession switches cleanly between input and output; the mic is released when leaving the Tuner

## Blocked by

- 09
