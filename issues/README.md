# GuitarKit — Issues

Tracer-bullet vertical slices derived from [`../docs/PRD.md`](../docs/PRD.md). Build in dependency order; each slice is demoable on its own.

| # | Slice | Type | Blocked by |
|---|---|---|---|
| 01 | App shell + rotary nav + design-system skeleton | HITL | — |
| 02 | Audio capture + first-run permission priming | AFK | 01 |
| 03 | Pitch detection engine (MPM) + raw readout | AFK | 02 |
| 04 | Music/tuning domain model | AFK | — |
| 05 | Detection-wiring: targeted tuning session | AFK | 03, 04 |
| 06 | Headstock hero UI | HITL | 05 |
| 07 | Visualization variants + dev-config panel | HITL | 06 |
| 08 | Chromatic mode | AFK | 06 |
| 09 | Instruments + presets + per-instrument headstocks | AFK | 04, 06 |
| 10 | Tuning/instrument picker + persistence | AFK | 09 |
| 11 | Capo control | AFK | 09 |
| 12 | Custom tuning editor | AFK | 10, 13 |
| 13 | Tone generator + AudioSession coordinator | AFK | 09 |
| 14 | Metronome engine | AFK | 13 |
| 15 | Metronome face | HITL | 14 |
| 16 | Metronome config | AFK | 15 |
| 17 | Harmony domain model | AFK | — |
| 18 | Circle-of-fifths explorer | HITL | 17 |
| 19 | Fretboard engine + tuning-aware scales | AFK | 17, 04, 13 |
| 20 | Chord voicings | AFK | 19 |
| 21 | Circle hub cross-links | AFK | 18, 19, 20 |
| 22 | Settings | AFK | 06 |
| 23 | Accessibility pass | HITL | most |

**Spine:** #03 (mic → pitch → screen) is the tracer-bullet spine. **#13 folds in the AudioSession coordinator.** Finger-number labeling, Karplus–Strong, and the reactive backdrop ride along as feature flags inside their slices.
