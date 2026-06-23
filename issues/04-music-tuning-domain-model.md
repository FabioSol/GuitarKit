# 04 — Music/tuning domain model

> Type: AFK · Source: docs/PRD.md · Stories: 23

## What to build

The pure domain layer: `Note` (pitch class + octave) ↔ MIDI, a `Temperament` abstraction (`EqualTemperament`, plus per-string sweetened cent offsets supported in the model), frequency derivation `target = referenceA · 2^((midi−69)/12) · 2^(cents/1200)`, reference-pitch calibration, and capo transposition. No UI — this is the deterministic core, fully unit-tested.

## Acceptance criteria

- [ ] Note ↔ MIDI ↔ frequency conversions are correct across reference pitches (e.g., A=440/432/442)
- [ ] Capo shifts all targets by N semitones and clamps to 0–12
- [ ] Per-string sweetened cent offsets apply through `Temperament` (0 for equal temperament)
- [ ] Behavior covered by unit tests through the public interface

## Blocked by

None - can start immediately.
