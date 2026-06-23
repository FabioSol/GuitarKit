# 09 — Instruments + presets + per-instrument headstocks

> Type: AFK · Source: docs/PRD.md · Stories: 17, 18

## What to build

An `Instrument` model where each entry has a fixed string count (guitar 6/7/8, bass 4/5/6, ukulele, mandolin, banjo, violin/viola/cello), a peg/headstock layout (including the banjo's 5th peg and the violin's 2+2 pegbox), and categorized preset tunings (standard / drop / open / alternate). The headstock view renders correctly per instrument and the targeted tuner works for all of them.

## Acceptance criteria

- [ ] Each instrument entry has the correct string count, peg layout, and preset tunings
- [ ] The headstock renders correctly per instrument, including the banjo and violin oddities
- [ ] Selecting a preset re-renders the headstock and retargets detection

## Blocked by

- 04
- 06
