# GuitarKit — Codebase Audit (executive summary)

14 agents audited the codebase folder-by-folder (source + tests). Full detail per area is in the linked reports; this is the synthesized, prioritized plan.

**Overall health: good.** The pure domain layer (music theory, metronome timing, fretboard, tuning session) is correct and genuinely well-tested. Defects cluster in three places: **(1) the real-time audio + pitch DSP** (a data race, hot-path allocations, and a logic bug in the brand-new ensemble), **(2) SwiftUI render efficiency** (the nav and the Chords/Scales grids recompute heavily), and **(3) test coverage of the stateful/UI surfaces** (mode transitions, view models, and — most importantly — *realistic* guitar audio, which the current synthetic-only fixtures can't represent).

## Severity tally (bugs only, across all areas)
~37 bug-level findings: **6 HIGH**, ~21 MED, ~10 LOW. No crash-on-launch defects. The HIGHs are the ToneGenerator race, the ensemble agreement bug, the non-finite-input crash, the glass contrast-fallback, and the two efficiency storms (nav, Chords/Scales).

---

## P0 — Correctness bugs (fix first)

1. **Ensemble returns mismatched frequency + clarity** — `Domain/Pitch/PitchAlgorithm.swift:~104`. In the agreement branch it picks the estimate by clarity but tags it with the *other* detector's boosted clarity → up to 40 cents of arbitrary error. This is in the code we just added to fix flaky detection, and it's untested. → [domain-pitch.md]
2. **ToneGenerator data race** — `Audio/ToneGenerator.swift`. The main actor mutates `generator`/`envelopeTarget`/`envelopeGain` in `play`/`stop` while the render thread reads/writes the same `nonisolated(unsafe)` fields; the "render-callback-only" invariant doesn't actually hold. → [audio.md]
3. **Crash on non-finite pitch input** — `Domain/Music/PitchCalculator.swift:183`. `nearestNote(toFrequency: +Inf)` traps in `Int(.rounded())`; `cents`/`frequency` emit NaN. `ReferencePitch.init` also lets NaN through its clamp. → [domain-music.md]
4. **Glass opaque fallback is invisible** — `DesignSystem/GKGlass.swift:86`. Under Increase Contrast / Reduce Transparency the fallback fills chrome with `GKColor.background` — the same as the screen — so pills/chips/nav nearly vanish. Inverts its own purpose. → [design-system.md]
5. **Metronome is torn down on every nav switch** — `Features/Metronome/*` + `App/RootView.swift`. Its model is internal `@State` (not hoisted like Chords/Scales/Circle), and RootView's `switch` + `.id(selection)` rebuilds it each tool switch, so `shutdown()` runs every time and the "survives navigation" comments are false. → [features.md]
6. **MetronomeEngine.shutdown never detaches the player node** — `Audio/MetronomeEngine.swift` — risks a double-attach crash on re-entry. → [audio.md]
7. **TuningSession.clearLock leaves stale `deviationCents`/`zone`** — `Domain/Tuning/TuningSession.swift:137` (phantom UI state); and **Fretboard capo/fretCount ambiguity** lets `ascendingNotes()` emit pitches above the real instrument under a capo. → [domain-rest.md]
8. **RootView silently overrides the dark-first default** — `App/RootView.swift` `.preferredColorScheme` means `.system` users never get the documented dark default. → [app-shell.md]

## P1 — Efficiency (matters on the iPhone 13)

1. **Rotary nav render storm** — `Navigation/RotaryNavBar.swift`: all 40 glass coins instantiate every frame (~33 invisible but still composited) and `representativeSlots()` rebuilds a 40-entry dict on every body eval (~60×/sec mid-spin). Gate coin creation on visibility; derive from `selection`, not live `rotation`. → [app-shell.md]
2. **Chords/Scales per-cell recompute** — `ChordsView` rebuilds the voicing generator + library ~36×/render; `ScalesView` rebuilds the fretboard scale ~78×/render. Resolve once per render, pass into `cell(...)`; memoize derived lists on the VMs. → [features.md]
3. **Audio + DSP hot-path allocations** — every tap/tick callback spawns a `Task { @MainActor }` + copies a 4096-`Float` array on the real-time thread; MPM/YIN/preprocessor each allocate several `[Float]` per call (2× for ensemble) ~10×/sec. Lock-free scalar handoff + hoisted scratch buffers. → [audio.md], [domain-pitch.md]
4. **Smaller wins** — `FretboardScale.descendingNotes()` re-runs the full board scan; `ChromaticReadoutView` animates on the whole `PitchReading` so it re-animates every detector frame. → [domain-rest.md], [tuner-modes.md]

## P2 — Secondary correctness bugs

- **TunerView mode transitions** (3 MED): `.sheet(onDismiss:)` unconditionally restarts the mic; chromatic-off never resets the stale session; `scenePhase == .active` refreshes permission but never re-syncs the engine (mic can stay dead while "granted"). → [tuner-core.md]
- **Capo control**: clear-icon tap can increment instead of reset; VoiceOver decrement jumps straight to fret 0 instead of −1. → [tuner-modes.md]
- **Wrong peg highlighted** on duplicate target frequencies; uncancelled `asyncAfter` celebration timer. → [tuner-core.md]
- **ChordVoicingGenerator window off-by-one** (`:174`) can scan past the one-hand span on short boards. → [domain-harmony.md]
- **MPM.keyMaxima boundary fragility** can drop the final hump for low notes near buffer length. → [domain-pitch.md]
- **CustomTuningStore** silently discards all saved tunings on any decode failure (no migration/versioning). → [tuner-modes.md]

## P3 — Test coverage (the audit's biggest theme — and tied to the open detection issue)

1. **Realistic guitar audio is untestable today.** `SignalGenerators` only makes perfect, zero-phase, non-decaying harmonic tones — exactly the case detectors never miss. There are **no tests for weak-fundamental/harmonic-dominant low notes, inharmonicity, decay, or tone-in-hum** — i.e. the real "flaky low strings" cases. Add fixtures + tests through MPM/YIN/ensemble/`process`. **Do this before/with the HPS work.** → [tests-audio-pitch.md]
2. **Ensemble disagreement + preprocessor-helps are untested**; the one ensemble test is vacuous (the +0.1 boost is hidden by the clamp on a ~1.0 sine). Fix the wrong "−45 dBFS" comment (gate is −52). → [tests-audio-pitch.md]
3. **Stateful/UI surfaces have ~zero tests**: nav math, `TuningSessionModel` (capo shifts targets, latch/completion haptics fire once on edges — both injectable), TunerView transitions, and the Chords/Scales/Metronome view models (BPM clamp, accent resize, voicing cycle/clamp). → [app-shell.md], [tests-ui.md], [features.md]
4. **Settings persistence is only partly tested** — metronome group + experimental flags + accent + confirmationSound are default-only (never round-tripped/reset-checked); add a `loadEnum` garbage-value fallback test. → [settings.md], [tests-ui.md]
5. **Curated chord library unverified** — 14 of ~17 hand-authored shapes have no test asserting they sound their chord; a fret typo ships a wrong chord silently. Test the generator beyond C-major/standard tuning. → [domain-harmony.md]
6. **Make store test suites parallel-safe** (UUID-per-suite) and pull the non-asserting `HeroSnapshotGenerator` out of the default test plan. → [tests-ui.md]

## P4 — Maintainability & cleanup

- **Decompose the `TunerView` god-object** (11 `@State`) into a testable `TunerCoordinator` mode state machine — fixes both the structure and the P2 transition bugs and unblocks testing. → [tuner-core.md]
- **Dedupe Chords/Scales view models** (shared audio trio, tuning init, `LabelMode`, handedness, two divergent degree-label systems). → [features.md]
- **Delete dead code**: `ToolPlaceholderView`, `RawPitchReadoutView`, the unused `showFingerNumbers` flag; fix the false "lazy face building" / `GlassEffectContainer` / metronome-survives-nav comments. → [app-shell.md], [tuner-core.md], [features.md]
- **Assets/a11y**: define the empty `AccentColor.colorset` (system controls currently default to blue, colliding with the "flat" semantic); give the fixed-96pt hero note Dynamic-Type scaling. → [design-system.md]

---

## Per-area reports

| Area | Report | Bugs (H/M/L) |
|---|---|---|
| App shell & nav | [app-shell.md](app-shell.md) | 0 / render-storm + colorScheme / cleanup |
| Audio | [audio.md](audio.md) | race + RT-safety (2H) + lifecycle |
| Design System | [design-system.md](design-system.md) | 1H (contrast) + accent + Dynamic Type |
| Domain/Pitch (DSP) | [domain-pitch.md](domain-pitch.md) | 1H (ensemble) + 4M |
| Domain/Music | [domain-music.md](domain-music.md) | non-finite crash + clamp |
| Domain/Harmony | [domain-harmony.md](domain-harmony.md) | voicing off-by-one + coverage |
| Domain/Fretboard·Instruments·Metronome·Tuning | [domain-rest.md](domain-rest.md) | clearLock + capo range |
| Tuner core | [tuner-core.md](tuner-core.md) | 3 transition bugs + god-object |
| Tuner modes | [tuner-modes.md](tuner-modes.md) | capo gesture/VoiceOver + store |
| Features | [features.md](features.md) | 2H efficiency + metronome-nav lie |
| Settings | [settings.md](settings.md) | 0 bugs; coverage + picker consistency |
| Domain tests | [tests-domain.md](tests-domain.md) | strong suite; branch gaps |
| Audio & Pitch tests | [tests-audio-pitch.md](tests-audio-pitch.md) | realistic-audio gap (1B/3H) |
| UI / Feature tests | [tests-ui.md](tests-ui.md) | untested stateful surfaces |

## Suggested sequencing
1. **P0 bugs** (each is small + self-contained; the ensemble + ToneGenerator + non-finite ones are the user-facing ones).
2. **P3.1 realistic-audio fixtures** — do this *with* the detection work; it makes the flaky-low-string problem (and the planned HPS) actually testable.
3. **P1 efficiency** before device testing on the iPhone 13.
4. **P4 `TunerCoordinator` extraction**, which unlocks **P2 transition bugs** + their tests.
5. The remaining coverage (P3) and cleanup as you touch each area.
