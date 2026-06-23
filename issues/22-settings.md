# 22 — Settings

> Type: AFK · Source: docs/PRD.md · Stories: 14, 23, 25, 64, 65

## What to build

A grouped settings screen, with per-tool ephemeral choices staying in their tools and only global persistent prefs here: Tuning (reference pitch; Advanced: sweetened profile, in-tune sensitivity), Feedback (haptics, sound + choice), Appearance (theme, accent), Instrument (handedness, default labeling), an Advanced disclosure (experimental flags; dev-only flags compiled out of release), and About (version, on-device privacy statement, rate, contact). The Advanced disclosure is where the otherwise-hidden sweetened-tuning UI lives.

## Acceptance criteria

- [ ] Global prefs are present and persisted; Advanced options are tucked under a disclosure
- [ ] Reference-pitch calibration and the sweetened-tuning profile are reachable (under Advanced)
- [ ] The privacy statement states on-device / no-tracking / no-accounts

## Blocked by

- 06
