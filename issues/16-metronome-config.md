# 16 — Metronome config

> Type: AFK · Source: docs/PRD.md · Stories: 39, 40, 41, 42, 43

## What to build

The metronome's musical configuration: common + custom time signatures (the beat-ring redraws to the beat count), subdivisions (quarter / eighth / triplet / sixteenth), tap-a-dot-in-the-ring to cycle accent → normal → muted, a curated set of click sounds with distinct accent / normal / subdivision timbres, and an optional per-beat haptic that enables silent (visual + touch only) practice.

## Acceptance criteria

- [ ] The beat-ring redraws to the selected time signature; tapping a dot cycles accent/normal/muted
- [ ] Subdivisions play between beats
- [ ] The sound set is selectable with audibly distinct downbeat/subdivision; a per-beat haptic toggle enables silent practice

## Blocked by

- 15
