# 12 — Custom tuning editor

> Type: AFK · Source: docs/PRD.md · Stories: 26, 27, 28, 29, 30, 31, 32

## What to build

An editor that opens as a duplicate of the current tuning (or blank). Each string is edited with a semitone stepper; the user can tap a string to hear it (tone generator) and optionally capture a string by playing it. Saving auto-suggests a name from the note spelling, stores the tuning under the instrument's Custom category, and supports later edit and swipe-to-delete. A string set wildly outside the instrument's range produces a gentle, non-blocking warning.

## Acceptance criteria

- [ ] Create from the current tuning (default) or blank; nudge each string ±1 semitone
- [ ] Hear a string while editing; optionally capture a string by playing it
- [ ] Save with an auto-suggested name; later edit and swipe-to-delete custom tunings
- [ ] Out-of-range strings warn without blocking the save

## Blocked by

- 10
- 13
