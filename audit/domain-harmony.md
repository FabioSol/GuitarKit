# Audit — Domain/Harmony

**Scope:** Chord.swift, ChordQuality.swift, ChordVoicing.swift, ChordVoicingGenerator.swift, StandardChordLibrary.swift, Scale.swift, CircleOfFifths.swift, Key.swift, DiatonicTriads.swift, PitchClass+Intervals.swift, SpelledNote.swift

**Health:** Music-theory core (intervals, scales, qualities, key signatures, diatonic triads, circle math) is correct and well tested — I found no interval/recipe errors and verified every chord recipe and scale against the existing assertions. The weak spot is the voicing layer: `ChordVoicingGenerator` is a genuine heuristic with one real correctness bug (it can sound notes the chord doesn't contain) plus a span-guarantee gap, and the generator + curated library have notable test-coverage holes. The rest is solid, idiomatic value-type code.

## Bugs & correctness

- [BUG|HIGH] `ChordVoicingGenerator.swift:189-207` — `applyRootInBassPreference` can leave a NON-root note in the bass, contradicting its own contract and the `testCMajorGeneratedShapeIsRootPosition` invariant for chords where the root is unreachable low. It finds the lowest string playing the root and mutes everything *below* it, but if that root string is e.g. index 3, strings 0–2 are muted and the result is fine — however when NO string plays the root, it silently does nothing and the bass is some other chord tone. That is documented as intentional, so it is not the bug. The real issue: the existing test only checks C major (whose root E-string is reachable). For roots like `Chord(root: .b, quality: .major)` on a standard board the lowest in-window B may sit on a high string, muting strings 0–2 and producing a thin 3-string shape that still passes "subset of chord tones" but is musically a poor/sparse voicing the fallback is supposed to catch — acceptable, but untested. Fix: add coverage asserting bass == root for several roots, and decide explicitly whether a non-root bass is allowed.

- [BUG|MED] `ChordVoicingGenerator.swift:174` — `for fret in start...max(start, to)` always scans at least `start...start` even when `to < start` (i.e. the window collapsed because `windowEnd < start`, e.g. high `minimumFret` near the end of a short board). This means a fret BEYOND `windowEnd` (namely `start`, which can exceed `windowEnd`) is considered, so a chosen fret can violate the `[windowStart ... windowStart+windowSpan]` window and the heuristic's "fits under one hand" promise. It is masked today only because the default board has `fretCount: 15` and `positionsToScan: 12`. Fix: guard `guard start <= to else { return nil }` before the loop instead of `max(start, to)`.

- [BUG|LOW] `ChordVoicing.swift:76-78` — `highestFret` counts open strings (fret `0`) as candidates but `lowestFrettedFret` excludes them. For an all-open shape (e.g. Em `022000`-style reduced to opens) `highestFret` is a positive fret while `lowestFrettedFret` is `nil`; the span check in `testEveryAlternateStaysWithinTheFretSpan` then `continue`s (guards on both being non-nil) and silently skips validation. Not wrong arithmetically, but the asymmetry means a shape mixing open strings with a fret-4 note reports span `4 - 1 = 3`, hiding the true physical reach from the open string. Fix: document the asymmetry or compute span from `min(all played frets)` when open strings sound.

- [BUG|LOW] `ChordVoicingGenerator.swift:130-132` — `for minFret in 0..<positionsToScan { guard minFret <= fretboard.fretCount else { break } }` — the guard can never fire: `positionsToScan` (12) is always ≤ a 15-fret board, and even on a tiny board `minFret < positionsToScan` bounds the loop first. Dead guard; harmless but misleading. Fix: loop `0..<min(positionsToScan, fretboard.fretCount + 1)` and drop the guard, or remove the guard.

## Efficiency

- `Key.signaturePosition` (`Key.swift:152-179`) rebuilds the full -7...+7 major-tonic table on every access (two `for`/`filter` passes constructing 15 `SpelledNote`s each), and `keySignature`, `sharpsOrFlats`, and `CircleOfFifths.majorIndex` all call it indirectly. For a wheel UI redrawing all 12 keys this is ~180 throwaway spellings per frame. MED. Cache the position→tonic map as a `static let`, or store the circle position on `Key` at construction (it is known in `major(circlePosition:)`).
- `CircleOfFifths.majorIndex` (`CircleOfFifths.swift:96-104`) does a linear `firstIndex` scan per call; `distance`, `clockwise`, etc. each call it twice. Fine at n=12 but a dictionary `[PitchClass: Int]` would make intent clearer. LOW.
- `Chord.notes`/`pitchClassSet` and `Scale.notes`/`pitchClassSet` recompute via `map` on every access (computed properties). Called repeatedly by the generator (`tones = chord.pitchClassSet` is cached once — good) but elsewhere could thrash. LOW; only matters if hot.

## Maintainability & practices

- `ChordVoicing.swift:67` `lowestFrettedFret` vs `:76` `highestFret` — inconsistent treatment of open strings (see BUG above) is the kind of subtle API asymmetry that invites caller bugs. Worth a one-line doc cross-reference or unifying the semantics.
- `ChordQuality.dominantThirteenth` keeps the 5th but drops the 11th, while `dominantEleventh` drops the 3rd — both documented, both defensible, but the omission policy differs per chord with no shared rationale constant. Consider documenting the omission rule in one place. NIT.
- `DiatonicTriads.classifyTriad` (`:103-115`) `default: return .major` silently swallows any non-standard interval pair (would arise if fed harmonic/melodic minor). Currently unreachable for major/natural-minor, but a `default` that fabricates a major triad could hide a future bug. Prefer `assertionFailure` in the default, or make it return optional. NIT.
- `Key.majorTonic` comment (`:91-101`) says "callers stay within ±7" but nothing enforces it; `transposed(by:)` wraps so out-of-range positions silently produce wrong spellings rather than failing. LOW.
- Naming: `StandardChordLibrary.Key` collides conceptually with the harmony `Key` (musical key) type. Both are `public`. A reader seeing `Key` in this domain could be confused. Consider `ChordKey` / `LibraryKey`. NIT.

## Test coverage gaps

- **No `ChordVoicingGeneratorTests` file beyond the shared `ChordVoicingTests`.** Specifically missing: (1) root-in-bass for roots other than C (the BUG above is untested); (2) behavior in NON-standard tunings (Drop D, or a non-guitar board) — the generator claims to work in any tuning but is only exercised on standard guitar; (3) the window/span bug at `:174` (high `minimumFret` on a short `fretCount` board); (4) `alternates` de-duplication and the "strictly higher last" property for chords other than C major.
- **No `ChordQualityTests`** — `symbol` strings (e.g. `"7♯5"`, `"m7♭5"`, `"6/9"`) are never asserted; a typo ships silently. `ChordTests` covers recipes but not labels.
- **No `StandardChordLibrary` audio-correctness sweep** — only C major and E major shapes are pinned to exact frets and only C major is verified to sound the right pitch classes. The other ~14 hand-authored shapes (A, G, D, the 7ths, the m7s) are NOT verified to sound exactly their chord's tones on a standard board. A typo in, say, `B7 x21202` would ship undetected. Add a parameterized test asserting `playedPitchClasses == chord.pitchClassSet` (or `isSubset`) for every library entry.
- **No `Scale` enharmonic/note-count tests** for the modes and pentatonics beyond what `ScaleTests` covers (verify present, but extended-mode membership e.g. Locrian/Lydian membership should be spot-checked if not already).
- **`CircleOfFifths.distance`, `neighbors`, and minor-key `clockwise`** — verify these are exercised (the minor-mode branch at `:63` and `majorIndex`'s minor seat math at `:100-102` are correctness-critical and easy to get off-by-a-third).

## Top 3 priorities

1. Fix the window off-by-one in `ChordVoicingGenerator.lowestChordToneFret` (`:174`) — `guard start <= to else { return nil }` — so generated shapes can never exceed the one-hand span on short boards.
2. Add a `StandardChordLibrary` test that every curated entry sounds exactly its chord's pitch-class set on a standard board — the library is hand-authored data where a single fret typo ships a wrong chord silently.
3. Test the generator beyond C major / standard tuning: root-in-bass for multiple roots and at least one non-standard tuning, pinning the "in-chord, root-in-bass, within span" invariants the heuristic promises.
