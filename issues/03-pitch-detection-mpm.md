# 03 — Pitch detection engine (MPM) + raw readout

> Type: AFK · Source: docs/PRD.md · Stories: spine

## What to build

A `PitchDetector` protocol and a McLeod Pitch Method (MPM) implementation on Accelerate/vDSP. Pipeline: RMS gate → band-pass pre-filter → MPM → parabolic interpolation → octave-error correction → smoothing (median + EMA). The detector can run against a recorded/synthetic signal feed so it is testable and so UI work doesn't require the mic. A bare screen shows the live detected frequency and nearest note name. Supports the full range including low bass via longer windows.

## Acceptance criteria

- [ ] Returns a stable frequency for sustained tones across the supported range (incl. ~41–82 Hz bass and octave-ambiguous cases) within tolerance
- [ ] Silence and noise are gated — no readout below the level threshold
- [ ] The screen shows the live detected frequency and nearest note name
- [ ] The engine is swappable behind `PitchDetector` and is exercised in tests against a recorded/synthetic feed

## Blocked by

- 02
