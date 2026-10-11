# Audit — Domain/Music
**Scope:** GuitarKit/Domain/Music/{Note.swift, PitchCalculator.swift, ReferencePitch.swift, Temperament.swift, Capo.swift}

**Health:** The core math is correct and unusually well-reasoned: MIDI↔Note round-trips cleanly even for negative octaves (floored division is genuinely needed and genuinely used), the equal-temperament/cents formulas are textbook-accurate, and test coverage of the happy paths is strong. The remaining issues are edge-case robustness — chiefly NaN/Inf inputs slipping past the validating wrappers — and a few untested boundaries, not arithmetic errors. No high-severity logic bugs found.

## Bugs & correctness
- [BUG|MED] `ReferencePitch.swift:49` — `Swift.max(minHz, Swift.min(maxHz, hertz))` does NOT clamp `NaN`. `Swift.min(466, .nan)` returns `.nan`, and `Swift.max(415, .nan)` returns `.nan`, so a NaN `hertz` survives as a stored value. Every downstream frequency (`referenceA.hertz * ...`) then becomes NaN, and `nearestNote`/`cents` produce NaN silently. Why: the type's whole premise is "once you hold a `ReferencePitch` it's valid" (line 22) — NaN/±Inf break that invariant. Fix: reject or coerce non-finite input first, e.g. `guard hertz.isFinite else { self.hertz = Self.standard.hertz; return }` (or clamp via a finite default) before the min/max clamp.
- [BUG|LOW] `PitchCalculator.swift:82` `frequency(midiNumber:centOffset:)` — `centOffset` is unbounded and unchecked; a NaN/Inf cent value (e.g. from a malformed `SweetenedTemperament` offset) yields a NaN frequency with no guard. Lower severity because offsets are app-supplied today, but it's a fragile public entry point. Why: same invariant gap as above on the cents axis. Fix: either document the precondition or guard `centOffset.isFinite`.
- [BUG|LOW] `PitchCalculator.swift:178` `nearestNote(toFrequency:)` — guards `hz > 0` but not `hz.isFinite`. A `+Inf` input gives `midiExact = +Inf`, and `Int(midiExact.rounded())` is a **trap/crash** (Double→Int conversion of a non-finite value is undefined and crashes). Why: detectors can in theory emit Inf; a pure function on the public API should never trap. Fix: `guard hz > 0, hz.isFinite else { return nil }`.
- [BUG|LOW] `PitchCalculator.swift:148` `cents(from:to:)` — guards positivity but not finiteness; `cents(from: .infinity, to: 440)` returns `+Inf` rather than a sane sentinel. Consistent with the gap above; a single `.isFinite` guard closes it.

## Efficiency
- No concerns. All operations are O(1) or O(strings); `targets(for:)` is a single `enumerated().map`. `EqualTemperament`/`SweetenedTemperament` are stateless/array-indexed. The repeated `pow`/`log2` calls are inherent to the formulas, not waste.

## Maintainability & practices
- [MAINT] `Note.swift:155` & `Capo.swift:49` — `Note.from(midiNumber:)` cannot fail (it normalizes any Int), so `Capo.transpose` will happily produce notes at absurd octaves if fed garbage. That's acceptable given clamped fret input, but the "always succeeds" contract means a wrong MIDI number fails silently rather than loudly. Consider a documented valid MIDI range (0...127) or a `from(midiNumber:)` variant that returns `nil` outside it for callers that want strictness.
- [MAINT] `PitchCalculator.swift:23` `PitchTarget: Equatable` over a `Double frequencyHz` — exact `==` on derived floats is brittle if two construction paths round differently. Fine for current tests (they use `accuracy:`), but worth a comment that `PitchTarget` equality is exact-bit equality, not musical equality.
- [NIT] `Temperament.swift:103` `SweetenedTemperament` ignores `stringCount` entirely while the protocol doc (line 41) advertises count-relative profiles. The seam exists but no implementation uses it; fine for v1, just note the doc slightly oversells current behavior.
- [NIT] `ReferencePitch.swift:36` comment mentions `private(set)` as an alternative — harmless, accurate.

## Test coverage gaps
- **Negative / out-of-range MIDI** — `NoteTests` round-trips only `0...108`. The carefully-written floored-division + modulo-normalization path for negative MIDI (`Note.swift:159,163`) has zero direct coverage. Add e.g. `Note.from(midiNumber: -1) == Note(.b, octave: -2)` and a negative-range round-trip loop.
- **Non-finite inputs** — no test feeds `NaN`/`Inf` to `ReferencePitch(hertz:)`, `frequency(centOffset:)`, `cents(from:to:)`, or `nearestNote`. The crash at `PitchCalculator.swift:183` (Inf→Int) and the NaN-clamp escape are both currently unguarded AND untested.
- **`nearestNote`** — no tests at all for this public method (exact-pitch → 0 cents, quarter-tone-sharp → +50c, sub-/super-range frequencies, non-440 reference). It's the inverse of the core formula and deserves direct coverage.
- **`PitchCalculator.frequency(midiNumber:)` overload** — tested only via the `Note` overload; the raw-Int entry point used by `nearestNote` isn't asserted directly.
- **Capo at non-octave frets through frequency** — frequency is asserted only for fret 2, 12, 15; a mid-range fret (e.g. 5 → ×2^(5/12)) ratio isn't checked.

## Top 3 priorities
1. Guard non-finite inputs across `PitchCalculator.nearestNote` (prevents a real Inf→Int **crash** at line 183), `cents`, and `frequency`.
2. Fix `ReferencePitch.init` so `NaN`/`±Inf` cannot bypass the clamp and poison every derived frequency.
3. Add negative-MIDI and non-finite-input tests — the most carefully-written, least-covered code in the module.
