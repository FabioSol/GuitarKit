# 19 — Fretboard engine + tuning-aware scales

> Type: AFK · Source: docs/PRD.md · Stories: 50, 51, 55, 56, 57, 58, 59

## What to build

A tuning-aware fretboard engine (per-string pitch + capo → fret positions) and the Scales tool built on it: pick a root + scale/mode and the notes highlight across a horizontal neck with the root emphasized, playable ascending/descending. Includes a global left/right handedness mirror, a labeling toggle (note names / scale degrees; finger numbers behind a feature flag), an orientation flip, and a `Current tuning ⇄ Standard` override.

## Acceptance criteria

- [ ] A scale highlights correctly for the active tuning + capo, root emphasized, and plays ascending/descending
- [ ] Handedness mirrors the fretboard; labels toggle between names and degrees; orientation flips
- [ ] The `Current ⇄ Standard` override switches between active-tuning and standard-tuning mapping
- [ ] Fretboard mapping is covered by unit tests

## Blocked by

- 17
- 04
- 13
