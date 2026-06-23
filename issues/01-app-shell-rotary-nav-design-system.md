# 01 — App shell + rotary nav + design-system skeleton

> Type: HITL · Source: docs/PRD.md · Stories: 1, 60, 61

## What to build

The app launches directly into a Tuner placeholder (no hub). A custom 5-item rotary/arc navigation sits at the bottom (`Tuner · Metronome · Circle of Fifths · Chords · Scales`); all five are always visible and tapping any one animates it to the center along the shortest path with circular/infinite wrap (tap-only, no drag). Five placeholder tool screens exist behind the nav. Establish the design-system foundation: dark-first theme (light supported), semantic colors (sharp-red / flat-blue / tuned-green) and the purple accent, SF Pro / SF Pro Rounded typography with tabular figures, and Liquid Glass wrappers for the chrome layer. Lock the project to an iPhone target, portrait-only.

## Acceptance criteria

- [ ] App launches straight to the Tuner placeholder; no home/hub screen
- [ ] Rotary nav shows all 5 tools; tapping any centers it via shortest-path rotation with infinite wrap; tap-only
- [ ] Reduce Motion makes the rotation cross-fade instead of spin
- [ ] Design tokens (semantic + accent colors, type scale with tabular figures, glass chrome wrappers) are available app-wide in both dark and light
- [ ] Project target is iPhone-only and orientation is locked to portrait
- [ ] Rotary nav exposes proper tab semantics to VoiceOver (labeled, "n of 5, selected")

## Blocked by

None - can start immediately.
