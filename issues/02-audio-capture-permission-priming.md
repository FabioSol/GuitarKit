# 02 — Audio capture + first-run permission priming

> Type: AFK · Source: docs/PRD.md · Stories: 62, 63

## What to build

On first launch only, a brief value screen explains why the mic is needed, then triggers the OS microphone prompt and returns to the Tuner; every later launch goes straight to the Tuner. Wire up `AVAudioEngine` input capture and show a live input-level meter that visibly responds to sound, proving audio flows end-to-end. A denied permission shows a friendly, recoverable state that deep-links to Settings.

## Acceptance criteria

- [ ] First launch shows the priming screen before the OS mic prompt; subsequent launches skip it
- [ ] A live input-level indicator visibly reacts to sound
- [ ] Denying the mic shows a recoverable state with a deep link to Settings (no dead end)

## Blocked by

- 01
