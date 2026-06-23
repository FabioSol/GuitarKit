# 11 — Capo control

> Type: AFK · Source: docs/PRD.md · Stories: 24

## What to build

A quiet "Capo" chip on the Tuner face. Tapping it activates the capo and reveals a counter (`+N`) and a delete/clear icon; each subsequent tap increments, clamped to 0–12. The capo shifts all string targets up by N semitones and the headstock shows the shifted note names. The control is exposed as a VoiceOver-adjustable element.

## Acceptance criteria

- [ ] The chip increments on tap and shows the counter + delete icon; delete resets to 0; value clamps 0–12
- [ ] All targets shift by the capo amount and the headstock shows capo'd note names
- [ ] Exposed as a VoiceOver-adjustable element ("Capo, N frets")

## Blocked by

- 09
