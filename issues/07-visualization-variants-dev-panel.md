# 07 — Visualization variants + dev-config panel

> Type: HITL · Source: docs/PRD.md · Stories: 9

## What to build

Multiple `TunerVisualization` implementations behind one interface — at least a radial ring and a linear meter (needle/strobe as further candidates) — switchable at runtime via a developer config / feature-flag panel that also live-tunes the in-tune threshold and the smoothing. This exists specifically to A/B the hero's feel before committing to a final visualization.

## Acceptance criteria

- [ ] At least radial-ring and linear-meter visualizations are interchangeable at runtime behind one interface
- [ ] The dev panel switches visualization and adjusts threshold + smoothing live
- [ ] Dev-only controls are compiled out of release builds

## Blocked by

- 06
