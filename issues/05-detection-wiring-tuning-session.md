# 05 — Detection-wiring: targeted tuning session

> Type: AFK · Source: docs/PRD.md · Stories: 3, 4, 5, 6, 7

## What to build

A tuning-session state machine that consumes the detected pitch and the active tuning (standard guitar to start) and drives the targeted-tuning behavior: auto-detect the nearest string, compute deviation in cents (with direction), an optional next-string nudge, a tap-to-lock manual override, hold ~0.5–1s in tolerance to confirm → latch the string green, and an all-green completion state. UI here is minimal/placeholder (text or a simple meter) — the headstock arrives in slice 06. This slice is about the logic being correct and demoable.

## Acceptance criteria

- [ ] Playing any string auto-selects the nearest target and shows deviation in cents with direction
- [ ] Tapping a target manually locks onto it (override), even for a wildly out-of-tune string
- [ ] A string latches "in tune" only after being held in tolerance for ~0.5–1s and stays latched for the session
- [ ] When all strings are latched, a completion state is reached
- [ ] The state machine is covered by unit tests fed scripted pitch sequences

## Blocked by

- 03
- 04
