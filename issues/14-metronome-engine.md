# 14 — Metronome engine

> Type: AFK · Source: docs/PRD.md · Stories: 36

## What to build

A sample-accurate metronome built on pre-scheduled `AVAudioPlayerNode` buffers (never a `Timer`, which drifts). It plays and stops a steady click at a fixed tempo. The beat-sequencing logic (what plays when) is separated from audio output so it can be unit-tested on its own.

## Acceptance criteria

- [ ] Plays a steady, drift-free click at a fixed tempo with start/stop
- [ ] Timing comes from pre-scheduled audio buffers, not a `Timer`
- [ ] Beat-sequencing logic is covered by unit tests independent of audio output

## Blocked by

- 13
