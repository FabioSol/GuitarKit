# 20 — Chord voicings

> Type: AFK · Source: docs/PRD.md · Stories: 52, 53, 54

## What to build

The Chords tool on top of the fretboard engine: pick a root and a quality (the rich set) and see a playable voicing for the active tuning, generated from the string pitches, with a curated standard-tuning library as a quality fallback. Cycle through alternate voicings up the neck. Default to the vertical chord-box orientation. Play the chord (block or strummed). Respects handedness, labeling, and the `Current ⇄ Standard` override.

## Acceptance criteria

- [ ] Selecting a root + quality shows a playable voicing for the active tuning and can cycle alternates up the neck
- [ ] The standard-tuning library is used as a fallback where generation is weak; the override is respected
- [ ] The chord plays (block/strummed); voicing generation is covered by unit tests

## Blocked by

- 19
