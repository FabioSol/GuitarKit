# 10 — Tuning/instrument picker + persistence

> Type: AFK · Source: docs/PRD.md · Stories: 2, 19, 20, 21, 22

## What to build

A selector pill on the Tuner opens a sheet: a vertical accordion with a pinned Recents/Most-used group (seeded with sensible defaults that wash out as real usage accumulates), the current instrument expanded (guitar as the cold-start default), and other instruments collapsed in a stable canonical order. Each instrument shows its categorized presets plus a "＋ Create custom" row. The last-used instrument and tuning, plus usage counts, persist on-device and restore on next launch.

## Acceptance criteria

- [ ] Picker shows pinned Recents (seeded, then usage-driven), the current instrument expanded, others collapsed in a stable order
- [ ] The last-used instrument + tuning is restored on next launch
- [ ] Usage counts are tracked and ranked on-device only (no network)

## Blocked by

- 09
