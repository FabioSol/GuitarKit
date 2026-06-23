# 15 — Metronome face

> Type: HITL · Source: docs/PRD.md · Stories: 37, 38

## What to build

The metronome's UI: a circular tempo dial whose primary gesture is a vertical drag (up = faster, down = slower), with rotary tracking also supported. A tap-tempo button and ±1 steppers offer alternate input. The BPM number is centered (SF Rounded, tabular figures), range 30–300. A beat-ring around the dial shows one dot per beat with the downbeat in the accent color. The dial is exposed as a VoiceOver-adjustable element.

## Acceptance criteria

- [ ] Vertical drag changes BPM (up = faster); rotary drag also works; tap-tempo and ±1 steppers set tempo; range 30–300
- [ ] The beat-ring lights per beat with the downbeat accented
- [ ] The dial is exposed as a VoiceOver-adjustable element (swipe up/down = ±1)

## Blocked by

- 14
