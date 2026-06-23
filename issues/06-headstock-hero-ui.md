# 06 — Headstock hero UI

> Type: HITL · Source: docs/PRD.md · Stories: 8, 9, 10, 11, 12, 13

## What to build

Replace the placeholder with the hero: a headstock-shaped view with stylized pegs in their physical positions (standard guitar), highlighting the detected/locked string. One `TunerVisualization` (linear cents meter) shows flat/sharp/in-tune with direction. Semantic colors (sharp-red / flat-blue / tuned-green) are used but never as the sole signal — position, shape, motion, and haptics reinforce state. In-tune at ≤±3¢ and "perfect" at ≤±1¢ each fire distinct haptics. The all-green finish triggers a restrained completion flourish that degrades under Reduce Motion. The hero is solid content (no glass).

## Acceptance criteria

- [ ] Headstock shows pegs in physical positions; the active string's peg highlights
- [ ] The cents meter reads flat/sharp/in-tune; green ≤±3¢ and perfect ≤±1¢ fire distinct haptics
- [ ] In-tune state is distinguishable without relying on color (position/shape/motion/haptic)
- [ ] All-green triggers a restrained flourish that degrades to a simple state change under Reduce Motion

## Blocked by

- 05
