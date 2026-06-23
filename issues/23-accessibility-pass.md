# 23 — Accessibility pass

> Type: HITL · Source: docs/PRD.md · Stories: 13, 66, 67, 68

## What to build

A cross-cutting audit and hardening pass: VoiceOver semantics for the custom rotary nav, tempo dial, and capo; Dynamic Type across all screens; Reduce Transparency / Increase Contrast falling back to opaque surfaces; Reduce Motion fallbacks for every spin/flip (rotary nav, hero flip, completion flourish, circle rotation); and verification that tuning state is distinguishable without color. Accessibility is built into each slice as it lands — this slice is the final verification that the whole app holds together.

## Acceptance criteria

- [ ] VoiceOver can operate the nav, tempo dial, and capo with correct traits and labels
- [ ] Dynamic Type scales text across screens without breaking layouts
- [ ] Reduce Transparency / Increase Contrast → opaque surfaces; Reduce Motion → all spins/flips degrade gracefully
- [ ] Tuning state (sharp/flat/in-tune) is distinguishable without relying on color

## Blocked by

- Most feature slices (notably 01, 06, 15, 18); run as a final hardening pass
