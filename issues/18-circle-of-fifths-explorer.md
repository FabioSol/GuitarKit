# 18 — Circle-of-fifths explorer

> Type: HITL · Source: docs/PRD.md · Stories: 44, 45, 48, 49

## What to build

The self-contained interactive circle (explorer level — cross-links come later in slice 21). Outer ring = major keys, inner ring = relative minors. Tapping a segment selects that key: it rotates to the top "home" position (or simply highlights under Reduce Motion) and plays its scale. A details panel shows the key signature, relative minor, and diatonic chords. The circle respects the current instrument, and the selection is preserved when leaving and returning.

## Acceptance criteria

- [ ] Tapping a key (major or minor ring) rotates it to top (or highlights under Reduce Motion) and plays its scale
- [ ] The details panel shows signature, relative minor, and diatonic chords
- [ ] The selection is preserved when navigating away and back

## Blocked by

- 17
