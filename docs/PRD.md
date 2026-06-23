# GuitarKit — Product Requirements Document

> Status: Draft (synthesized from design/grill session, 2026-06-22)
> Platform: iOS 26.5, iPhone-only, portrait-only, SwiftUI
> Distribution: Free, no ads, no accounts, no tracking, fully on-device

---

## Problem Statement

Guitarists (and other string players) want to tune quickly and accurately, and to keep a few essential practice tools — metronome, harmony reference, chord/scale shapes — in one place. Most existing tuners are either ad-laden, cluttered, single-purpose, or assume standard guitar tuning and fall apart the moment you use a different instrument or an open tuning. As a beginner, the user also wants tools that *teach*, not just display.

## Solution

**GuitarKit** is a free, ad-free, beautifully minimal iOS toolkit whose hero is a fast, accurate, multi-instrument tuner. The app launches straight into the tuner (zero setup for returning users) and surrounds it with a metronome, an interactive circle of fifths, and tuning-aware chord and scale visualizers — all sharing one design language and cross-linked so the "kit" feels like a single coherent app rather than five separate ones.

Everything is tuning-aware: the tuner, the chord shapes, and the scale maps all reflect the *currently selected instrument and tuning* (including custom open tunings and a capo), which is the core differentiator.

---

## User Stories

### Tuner — core
1. As a player, I want the app to open straight into the tuner, so that I can start tuning with zero navigation.
2. As a returning player, I want the app to remember my last instrument and tuning, so that I never re-configure for my daily setup.
3. As a player, I want to play any string and have the app auto-detect which string I'm tuning, so that I don't have to tell it first.
4. As a player, I want a gentle hint of which string to tune next, so that as a beginner I have guidance, while still being free to tune in any order.
5. As a player, I want to tap a string indicator to lock onto that target manually, so that a wildly out-of-tune string doesn't get matched to the wrong note.
6. As a player, I want a string to confirm "in tune" only after I hold it steady briefly, so that the indicator doesn't flicker as I pass through pitch.
7. As a player, I want each tuned string to latch green and stay green for the session, so that "all strings green" is a real, stable finish line.
8. As a player, I want a satisfying but restrained celebration when all strings are in tune, so that finishing feels rewarding without being gaudy.
9. As a player, I want to see how flat or sharp I am and in which direction, so that I know which way to turn the peg.
10. As a player, I want the indicator shaped like my instrument's headstock with pegs in their real positions, so that the highlighted peg maps to the actual peg my hand reaches for.
11. As a player, I want clear "in tune" (≤±3¢) and "perfect" (≤±1¢) feedback, so that I can tune to a standard I trust.
12. As a player, I want a haptic tick when a string reaches in-tune and perfect, so that I can tune while watching my hands instead of the screen.
13. As a colorblind player, I want in-tune state conveyed by position, shape, motion, and haptics — not color alone — so that I can tune reliably.
14. As a player in a quiet space, I want confirmation sounds off by default, so that the app stays silent backstage or in a lesson.
15. As a player, I want a chromatic mode that names whatever note I play, so that I can tune any instrument or check any pitch without choosing a tuning.
16. As a player, I want switching to chromatic to feel thematic (a hero flip revealing a tuning-fork motif), so that the app feels crafted.

### Tunings & instruments
17. As a multi-instrument player, I want presets for guitar, bass, ukulele, mandolin, banjo, and the violin family, so that one app tunes all my instruments.
18. As a player of extended-range instruments, I want 7/8-string guitar and 5/6-string bass as their own entries, so that the headstock and presets are correct.
19. As a guitarist, I want guitar shown first by default on first launch, so that the common case is immediate.
20. As any returning player, I want my current instrument expanded in the picker, so that a bassist isn't forced past guitar every time.
21. As a player, I want my most-used tunings pinned at the top, seeded with sensible defaults and quickly adapting to my real use, so that my favorites are one tap away without the list reshuffling under me.
22. As a player, I want tunings grouped by category (standard, drop, open, alternate, custom), so that I can find what I want.
23. As a player, I want to calibrate the reference pitch (A=415–466), so that I can match an ensemble or a recording.
24. As a player, I want a capo control that shifts all targets and shows the capo'd note names, so that I can tune accurately with a capo on.
25. As a meticulous player, I want sweetened (per-string) tuning available without cluttering the main UI, so that my guitar sounds in tune to the ear, not just mathematically.

### Custom tunings (editor)
26. As a player, I want to create a custom tuning starting from my current one, so that I'm one or two edits from what I want.
27. As a player, I want to start from a blank tuning when needed, so that I can build an unusual tuning from scratch.
28. As a player, I want to nudge each string up/down by semitone, so that I can set targets precisely.
29. As a player, I want to hear each string as I edit it, so that I can audition the tuning.
30. As a player, I want to optionally capture a string by playing it, so that I can save a tuning I dialed in by ear.
31. As a player, I want a sensible auto-suggested name from the note spelling, so that saving is fast.
32. As a player, I want to edit and swipe-to-delete my custom tunings, so that I can manage my library.

### Tone generator (tune by ear)
33. As a player, I want to tap a peg to hear its target pitch, so that I can tune by ear.
34. As a player, I want the reference tone to sustain until I stop it, so that I have time to match it.
35. As a player, I want detection to pause while a reference tone plays, so that the app doesn't hear its own tone.

### Metronome
36. As a practicing player, I want a precise, drift-free metronome, so that my timing practice is trustworthy.
37. As a player, I want to set tempo by dragging up/down (and optionally rotating the dial), so that it feels natural.
38. As a player, I want tap-tempo and fine ±1 steppers, so that I can set tempo however I think about it.
39. As a player, I want common and custom time signatures, so that I can practice odd meters.
40. As a player, I want subdivisions (eighths, triplets, sixteenths), so that I can practice against off-beats.
41. As a player, I want to tap a beat in the ring to cycle accent/normal/muted, so that I can build groupings like 7/8 = 3+2+2.
42. As a player, I want selectable click sounds with distinct downbeat/subdivision tones, so that I can hear the structure.
43. As a player, I want optional per-beat haptics, so that I can practice silently with visual + touch only.

### Circle of fifths
44. As a learner, I want to tap a key and see its signature, relative minor, and diatonic chords, so that I understand the key.
45. As a learner, I want to hear a key's scale and its chords, so that theory connects to sound.
46. As a learner, I want to tap a diatonic chord and jump to its diagram, so that I can play what I'm learning.
47. As a learner, I want to jump from a key to its scale on the fretboard, so that I can see where to play.
48. As a player, I want the circle to respect my current instrument, so that cross-links land on relevant shapes.
49. As a user, I want returning to the circle to preserve my selection, so that cross-tool exploration feels continuous.

### Chords & scales (fretboard)
50. As a player, I want chord and scale shapes for my *current* tuning, so that open tunings and capo are reflected.
51. As a player, I want to override to standard-tuning shapes, so that I can learn standard chords even while in an alternate tuning.
52. As a player, I want to pick a root and a (rich) chord quality and see a playable voicing, so that I can find any chord.
53. As a player, I want to cycle alternate voicings up the neck, so that I can choose a comfortable shape.
54. As a player, I want to hear a chord (block or strummed), so that I can confirm it.
55. As a player, I want to pick a root and scale/mode and see it on the neck with the root emphasized, so that I can learn the pattern.
56. As a player, I want to hear a scale ascending/descending, so that I learn its sound.
57. As a learner, I want to toggle labels between note names and scale degrees, so that I understand *why* a shape works.
58. As a left-handed player, I want a handedness toggle that mirrors the fretboard, so that diagrams match my instrument.
59. As a player, I want chord diagrams vertical and scale maps horizontal by convention, with the ability to flip, so that each reads naturally.

### Navigation, settings, onboarding, accessibility
60. As a user, I want a distinctive rotary nav where I tap any of the five tools to bring it to center, so that navigation is delightful and every tool is one tap away.
61. As a user, I want the rotary nav to cross-fade instead of spin when Reduce Motion is on, so that it's comfortable.
62. As a new user, I want a brief value screen before the mic permission prompt on first launch, so that I understand why and grant it.
63. As a user who denied the mic, I want a friendly, recoverable prompt that links to Settings, so that a misstep isn't fatal.
64. As a user, I want a clean settings screen with advanced options tucked away, so that the app stays simple but powerful.
65. As a privacy-conscious user, I want everything on-device with no tracking or accounts, so that I trust the app.
66. As a VoiceOver user, I want the custom nav, dial, and capo exposed with proper semantics, so that I can use the whole app.
67. As a user with Reduce Transparency / Increase Contrast on, I want Liquid Glass to fall back to opaque surfaces, so that everything stays legible.
68. As a user, I want Dynamic Type support, so that I can read the app at my preferred size.

---

## Implementation Decisions

### Architecture & app shell
- **App launches directly into the Tuner.** Tools are satellites, not a hub home screen.
- **Custom 5-item rotary/arc navigation**: `Tuner · Metronome · Circle of Fifths · Chords · Scales`. All five always visible; tap-to-center along shortest path; circular/infinite wrap; tap-only (no drag); tapping any tab jumps directly. Tuner default-centered. Settings reached via a gear (off-arc). Must expose full tab semantics to VoiceOver and cross-fade under Reduce Motion. Implemented with `GlassEffectContainer` so tabs morph as they rotate.
- **Cross-tool navigation preserves each tool's state**; jumping (e.g., circle → chord) loads context and returns continuously.

### Pitch detection
- **Roll-our-own McLeod Pitch Method (MPM)** on Accelerate/vDSP, behind a **swappable `PitchDetector` protocol**. Pipeline: mic tap → RMS gate → band-pass pre-filter → MPM → parabolic interpolation → octave-error correction → smoothing (median + EMA).
- Develop against a **recorded/synthetic signal feed** so UI work doesn't require the mic.
- **SwiftF0** (neural, CoreML/ONNX) kept as a future swappable "noisy-room" engine behind the same protocol. Caveats recorded: it's a Python lib (no iOS build), its range floor is 46.875 Hz (excludes standard bass and below), and its license must be verified before adoption.
- **Full frequency range supported including bass** via longer analysis windows for very low notes (~31–82 Hz); accept slightly slower lock-on at the very bottom.
- **AudioSession coordinator** owns record↔playback category switching and tears down the mic when leaving the Tuner.

### Music & tuning domain (pure)
- `Instrument` owns `[Tuning]`; string count is **fixed per instrument entry** (7/8-string guitars and 5/6-string basses are separate entries). Each instrument carries a **peg/headstock layout** (incl. banjo 5th peg, violin 2+2 pegbox).
- `Tuning = { name, category, strings: [Note] }`; `Note = { pitchClass, octave }`.
- **Frequency is always derived, never stored:** `target = referenceA · 2^((midi−69)/12) · 2^(cents/1200)`.
- `Temperament` abstraction returns per-string cent offsets; v1 ships `EqualTemperament` (0 offsets) with a `Sweetened` profile supported in the model (UI hidden under Advanced).
- Reference-pitch calibration and capo (semitone shift of all targets) operate through this derivation.

### Tuning session / targeting (pure state machine)
- Targeted mode: **any-order auto-detect** of nearest string + optional next-string nudge; **tap-to-lock override**; **hold ~0.5–1s to confirm → latch green**; "all green" completion.
- In-tune threshold **±3¢ (green)**, **±1¢ (perfect)** with haptic; thresholds + smoothing live behind dev config.
- Chromatic = a mode toggle (hero flip) that bypasses targets and names the nearest note.

### Tuner presentation
- Hero = **headstock-shaped, stylized (not skeuomorphic) pegs** in physical positions; highlights the detected/locked string. Hero is **solid content** (never glass), protecting semantic color contrast.
- Deviation shown via a **swappable `TunerVisualization`** (Radial ring + Linear meter built; Needle/Strobe candidates), selectable at runtime via a **dev config/feature-flag panel** that also tunes thresholds/smoothing. Final visualization chosen after feel-testing.
- **Color semantics (tentative): red = sharp, blue = flat, green = in tune** — never the sole signal.

### Picker & persistence
- Selector pill → sheet: **vertical accordion** with a **pinned Recents/Most-used group** (seeded prior that washes out with real use), **current instrument expanded** (guitar = cold-start default), others collapsed in stable canonical order; each shows categorized presets + "＋ Create custom."
- Capo = quiet chip on the Tuner face; active state shows a counter (`+2`) and a delete/clear icon; clamped 0–12; exposed as a VoiceOver-adjustable element; headstock shows shifted note names.
- **Persist/restore last-used instrument + tuning**, custom tunings, usage counts, and settings — all on-device.

### Custom tuning editor (M2)
- Opens as a **duplicate of the current tuning** (or blank); **per-string semitone stepper** primary, **tap-to-hear** (tone generator), **optional capture-by-playing** per slot; auto-suggested name from spelling; saved under Custom; swipe-to-delete; gentle out-of-range warning (non-blocking).

### Tone generator (M2)
- **Headstock tone-mode toggle**: tap a peg to play that string's target pitch; **tap-to-toggle sustain**; **detection pauses** while playing. Harmonic-rich oscillator for v1; **Karplus–Strong** plucked-string as a stretch.

### Metronome (M3)
- **Sample-accurate scheduling via pre-scheduled `AVAudioPlayerNode` buffers** — never `Timer`.
- **Circular tempo dial**: primary gesture **vertical drag** (up faster / down slower), rotary tracking also supported; **tap-tempo** + **±1 steppers**; range **30–300 BPM**; VoiceOver-adjustable.
- **Beat-ring** (one dot per beat, downbeat in accent); **tap a dot to cycle accent/normal/muted**.
- Common + custom time signatures; subdivisions (quarter/eighth/triplet/sixteenth); curated click sounds with distinct accent/normal/subdivision timbres; optional per-beat haptic (silent practice).

### Circle of fifths (M4)
- **Connected hub built on a self-contained explorer.** Build the explorer (B) first; wire cross-links (C) when Chords/Scales exist.
- **Wheel is a selector only**: tap a major (outer) or minor (inner) segment → **rotate-to-top** (Reduce Motion → static highlight) + plays its scale. **All hub actions live in the details panel** (diatonic chord chips → open in Chords; "View scale" → open in Scales) — spatial separation prevents tap-intent ambiguity.
- Respects current instrument; tapping a chord/key drives the rotary nav with context preloaded.

### Chords & scales (M5)
- **Tuning-adaptive fretboard engine, staged:** engine is tuning-aware from day one (needs per-string pitch + capo, already available); **generated scales first** (set membership), **generated chord voicings as the harder follow-on** with a **curated standard-tuning library** as a quality fallback. **`Current tuning ⇄ Standard` override toggle**.
- Chords: root × **rich quality set** (incl. 6, 6/9, 9, 11, 13, add9, 7♭9/♯9, m7♭5, dim7, …); primary voicing + cycle alternates; play (block/strummed).
- Scales: root × scale/mode (major, natural/harmonic/melodic minor, pentatonics, blues, 7 modes); full-neck highlight, root emphasized; play asc/desc.
- Shared fretboard: **Chords vertical / Scales horizontal** by default with flip toggle; **global handedness mirror**; **labeling toggle (note names / degrees)**; **finger-number labeling behind a feature flag, ship-conditional on quality**; root in accent.

### Visual identity
- **Dark-first**, both light + dark, "minimal but not plain."
- **Liquid Glass on the chrome/functional layer only** (rotary nav, selector pill, capo chip, toggles, sheets, gear). **No glass-on-glass.** Reduce Transparency / Increase Contrast → opaque fallback.
- Backdrop: **subtle static ambient gradient + a highly discreet grain texture** (doubles as anti-banding on OLED). Reactive ambient backdrop kept as a flagged experiment.
- **Accent: purple/violet** (magenta-leaning, away from indigo/blue so it never reads as "flat"). Single signature for v1; curated theme picker later.
- Typography: **SF Pro** + **SF Pro Rounded** for the hero note letter; **tabular figures on all live numerics**; all-system (Dynamic Type for free).

### Settings
- Principle: **per-tool ephemeral choices stay in the tool**; global persistent prefs live in Settings. Groups: Tuning (reference pitch; Advanced: sweetened profile, sensitivity), Feedback (haptics, sound + choice), Appearance (theme, accent), Instrument (handedness, default labeling), Advanced (sweetened profiles, experimental flags; dev flags compiled out of release), About (version, privacy statement, rate, contact).

### Cross-cutting infra
- **Feature-flag / config subsystem** (hero visualization variants, reactive backdrop, SwiftF0 swap, finger-number labeling, threshold/smoothing tuning).
- Project config: **iPhone target only, portrait-locked**.

### Build order (single launch, no time pressure)
- **M1** Tuner core → **M2** Tunings + custom editor + tone generator → **M3** Metronome → **M4** Circle of fifths → **M5** Chords + Scales. Cross-cutting from day one: onboarding/permission, settings, accessibility, shared design system.

---

## Testing Decisions

**What makes a good test here:** exercise *external behavior* through a module's public interface, not its internals. The pure domain modules are deterministic (given inputs → known note names, frequencies, cents, fret positions, beat patterns) and are where TDD is cheapest and highest-value — ideal for a first Swift project to build confidence.

**Modules to unit-test (priority — pure, deterministic):**
- **Music/tuning model**: MIDI↔note conversion; frequency derivation across reference pitches; equal-temperament correctness; sweetened per-string offsets; capo transposition.
- **Tuning session / targeting state machine**: feed scripted pitch sequences → assert detected string, deviation cents, in-tune/perfect transitions, hold-to-confirm latching, all-green completion, tap-to-lock override.
- **Harmony model**: circle-of-fifths relationships, key signatures, relative minors, diatonic chords; scale/mode note sets; chord-quality → interval/note sets.
- **Fretboard engine + voicing/scale generator**: given a tuning + capo, assert correct fret positions for scales and that generated chord voicings are valid and playable; standard-library fallback equivalence.
- **Metronome scheduling logic**: beat sequencing, accent patterns, subdivision counts, time-signature handling (the *what-plays-when* logic, separate from audio output).
- **Pitch detector**: run MPM against recorded/synthetic tones across the supported range (incl. low bass and octave-ambiguous cases); assert detected frequency within tolerance.

**Lighter / non-unit coverage:** audio I/O (AudioSession, synthesis output) and SwiftUI presentation are validated by manual/device testing and (optionally) snapshot tests; the hardware/realtime boundary is wrapped thin so the testable logic sits behind it.

---

## Out of Scope (v1)

- iPad-optimized layouts and landscape orientation (iPhone-only, portrait-only for v1).
- Chord finder (reverse: frets → chord name).
- Scale **position systems** (CAGED / 3-note-per-string overlays); v1 shows full-neck.
- Sweetened-tuning **UI** (capability in the model; exposed later under Advanced).
- Curated accent-**theme picker** (single purple signature for v1).
- Metronome setlists/song-tempo memory, programmable tempo changes, polyrhythms.
- Circle of fifths: modes exploration, secondary dominants, modulation animations.
- Reactive ambient backdrop, Karplus–Strong tone, finger-number labeling — all behind flags, ship-conditional.
- Tip jar / any monetization. No ads, accounts, or tracking ever.
- SwiftF0 engine (kept swappable; not v1).

---

## Further Notes

- **Accessibility is a day-one cross-cutting requirement**, not a retrofit: VoiceOver semantics for the custom nav/dial/capo, Dynamic Type, Reduce Motion (cross-fade fallbacks for the rotary nav, hero flip, completion flourish, circle rotation), Reduce Transparency / Increase Contrast (opaque glass fallback), and non-color-only tuning feedback (position + shape + motion + haptic).
- **The user is new to Swift** and wants heavily explanatory comments in the implementation to learn on the go.
- The **tentative hero visualization and color mapping** are expected to iterate; the dev-config panel exists specifically to A/B them.
- Verify SwiftF0's **license** before it is ever pulled in.
