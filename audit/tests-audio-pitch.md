# Audit — Audio & Pitch tests

**Scope:** `GuitarKitTests/Audio/{MPMPitchDetectorTests,AudioLevelTests,ToneOscillatorTests,FirstRunFlagTests,MicPermissionStateTests}.swift`, `GuitarKitTests/Pitch/{MPMTests,YINTests,PitchAlgorithmTests,PitchPreprocessorTests,PitchSmootherTests,SignalGenerators}.swift`, cross-referenced against `GuitarKit/Domain/Pitch/{MPM,YIN,PitchAlgorithm,PitchPreprocessor,PitchSmoother}.swift` and `GuitarKit/Audio/{PitchDetector,AudioLevel}.swift`.

**Health:** The pure-math layers (AudioLevel, ToneOscillator, PitchSmoother, the biquad band shape) are well covered with crisp, deterministic assertions. The pitch-detection tests, however, exercise almost exclusively **clean synthetic sines** — the one input type the algorithms never struggle with. The exact real-world failure modes the source was rebuilt to fix (weak-fundamental low strings, harmonic-dominant octave errors, decay, noise+tone, the preprocessor's effect on detection, ensemble disagreement) are essentially untested, so the suite would stay green while real low-string detection fails. There is also a real assertion bug in the detector tests.

## Test bugs & weak assertions

- **[BUG]** `MPMPitchDetectorTests.swift:43` — `test_process_belowLevelGate` comment claims a "−45 dBFS gate" but the detector's default `levelGateDB` is **−52** (`PitchDetector.swift:122`). The amplitude 0.0001 (≈ −80 dBFS) passes the test by a wide margin, but the test documents the wrong threshold and would not catch the gate being loosened from −52 to, say, −70. Use an amplitude just below the actual −52 dB gate (RMS ≈ 0.0025 for a sine ⇒ amplitude ≈ 0.0035) and a sibling case *just above* it to actually pin the boundary.

- **[HIGH]** `MPMPitchDetectorTests.swift:21-32` — The only "happy path" detector test feeds a **pure 220 Hz sine** through the full gate→preprocess→detect→smooth→resolve pipeline. Pure sines are exactly what every algorithm nails; this never exercises the ensemble/preprocessor on a hard input. It also runs only the default `.ensemble` algorithm — `setAlgorithm(.mpm/.yin)` paths are never driven through `process`. Add a harmonic-rich / decaying low-E case here.

- **[HIGH]** `PitchAlgorithmTests.swift:44-56` — `test_ensemble_corroboration_boostsClarityOverEither` asserts `ensemble.clarity >= max(mpm,yin)`. On any agreeing input the ensemble adds `+0.1` then clamps to 1 (`PitchAlgorithm.swift:106-107`); a pure G3 sine already scores ~1.0 for both, so `max` is ~1.0 and the assertion is satisfied by the clamp regardless of whether the +0.1 boost logic works. It would pass even if the boost were deleted. Assert against a mid-clarity input (e.g. a decaying/harmonic tone where clarity ~0.7) so the +0.1 is observable, and assert strictly greater.

- **[HIGH]** `PitchAlgorithmTests.swift` (whole file) — **No test exercises the ensemble disagreement path** (`PitchAlgorithm.swift:108-110`, "trust the more confident detector") nor the "only one fires" branches (`:111-113`). These are the branches that matter on flaky low strings where MPM octave-errors and YIN doesn't (or vice-versa). The agreement/clamp path is the *only* one covered.

- **[MED]** `MPMTests.swift:78-87` / `YINTests.swift:64-71` — The octave-resistance tests use a harmonic tone where the fundamental amplitude (0.4 / 0.5) is *only slightly* below the 2nd harmonic (1.0) and **all harmonics are perfectly in phase and perfectly harmonic**. Real guitar low strings have a fundamental that is far weaker (often 1/5–1/10 of the 2nd/3rd partials), inharmonic, and decaying. This test passes on a case the detector already handles and does not represent the failure mode. Add a case with `harmonicAmplitudes: [0.1, 1.0, 0.8, …]` at 82 Hz.

- **[MED]** `MPMTests.swift:96-101` / `YINTests.swift:82-88` — Noise rejection is tested only with **pure noise** (`Signal.noise`). The realistic failure is a **weak tone buried in noise** (mains hum + a quiet low E). There is no `noise + tone` mixture test, so the clarity gate's behavior on the actual ambiguous input is unverified. A loose gate that passes hum-dominated buffers would not be caught.

- **[MED]** `YINTests.swift:87` — `XCTAssertLessThan(estimate?.clarity ?? 1, 0.6)` only checks clarity is *below 0.6* on pure noise. The detector's default gate is **0.6** (`PitchDetector.swift:121`), so a noise clarity of 0.59 would pass this test yet be admitted by the real gate (≥ 0.6 boundary is `>=`). Tolerance is too loose relative to the production threshold; tighten to well below 0.6 (e.g. < 0.4) or assert the detector would reject it.

- **[MED]** `PitchPreprocessorTests.swift:42-45` — `test_highPass_attenuatesRumble` asserts 40 Hz gain `< 0.6`. A 2nd-order high-pass at 65 Hz gives only ~−5 dB (~0.56) at 40 Hz, so this barely passes and tolerates almost no attenuation — it would not catch the high-pass being effectively bypassed. The hum-killing claim (50/60 Hz) isn't tested at all; add a 50 Hz and 60 Hz assertion with a meaningful bound.

- **[MED]** `PitchPreprocessorTests.swift:64-74` — `test_preprocessedTone_stillDetectsSamePitch` runs only **YIN** on a **mid-band 146 Hz** tone. It never checks the preprocessor *helps* (or at least doesn't hurt) on the low-E case it exists for, never checks MPM, and never compares filtered-vs-unfiltered detection. The preprocessor's actual purpose — making a weak-fundamental low string detectable — is unverified end-to-end.

- **[LOW]** `MPMTests.swift:64-74` / `YINTests.swift:51-55` — Bass tests use **8192-sample** windows, but the live detector processes whatever the hardware buffer is (commented as ~4096 in `PitchDetector.swift:237`). MPM at 4096 explicitly can't resolve <~41 Hz; no test asserts the *4096-sample* low-E behavior that production actually runs. The window size used in tests does not match the integration path.

- **[LOW]** `PitchSmootherTests.swift:30-38` — `test_singleOutlier` uses `accuracy: 1.0` on an expected exactly-100 median. The median is mathematically exactly 100; the slack is harmless but masks that the EMA does move slightly. Fine, but the **even-window / partial-window** median behavior (`PitchSmoother.swift:76`, `count/2` upper-middle bias) is never tested, and a *sustained two-reading octave jump* (which a 5-median tolerates only briefly) isn't covered.

- **[LOW]** `SignalGenerators.swift:39-54` — `harmonicTone` produces only **perfectly harmonic, zero-phase, non-decaying** partials. There is no generator for **inharmonic** partials (stiffness: `n·f·√(1+Bn²)`), **decaying** envelopes, or **noise+tone** mixtures, so realistic-guitar tests simply *cannot be written* with the current fixtures. This is the root enabler of most coverage gaps below.

## Coverage gaps (esp. realistic guitar/low-string + ensemble + preprocessor)

- **Weak-fundamental / harmonic-dominant low notes (octave errors):** No test where the fundamental is much weaker than its harmonics at a *low* pitch (82 Hz / 41 Hz). This is the documented real-world failure and the reason MPM/YIN/preprocessor exist. The current octave tests are at 110 Hz with a near-equal fundamental — the easy case.
- **Inharmonic strings:** No fixture or test for stretched-partial (stiff-string) tones. Real low strings are inharmonic and that is what destabilizes autocorrelation detectors.
- **Decaying notes:** No test feeds an amplitude-decaying buffer. Clarity drops as a note decays; the loosened 0.6 clarity gate and −52 dB level gate are tuned for decay but no test verifies a decaying tail is still detected (or correctly dropped at the end).
- **Noise + tone mixtures:** Only pure tone or pure noise is tested. The clarity gate's discrimination on a tone-in-hum buffer is untested.
- **Preprocessor's effect on detection:** No before/after comparison showing the band-pass *improves* (or preserves) detection on a weak-fundamental low E. The biquad band shape is tested in isolation, but its job — changing detection outcomes — is not. Also untested: filter **statefulness across consecutive buffers**, `reset()` clearing delay memory, and `setCutoffs` re-tuning behavior.
- **Ensemble disagreement & single-fire paths:** Untested (see HIGH above). No test where MPM and YIN diverge >40 cents, nor where one returns nil. The "trust more confident detector" octave-error recovery is the ensemble's reason to exist.
- **Level/clarity gates at the boundary:** Both gates are only tested far from their thresholds. No "just above / just below" pair for either the −52 dB level gate or the 0.6 clarity gate, so drift in either constant goes uncaught.
- **Sample-rate variation:** Everything runs at 44.1 kHz. 48 kHz (common on iOS hardware) and the preprocessor's `configure`-on-rate-change path (`PitchPreprocessor.swift:123`) are untested.
- **Detector algorithm switching:** `setAlgorithm`, `setPreprocessing(enabled:)`, `setClarityThreshold`, `setLevelGate`, `setPreprocessorCutoffs` (the whole Tuner Lab live-tuning surface) are never driven through `process`.

## Test quality & maintainability

- Good: `assertFrequency` cents-based helpers (`MPMTests.swift:21`, `YINTests.swift:20`) are the right abstraction; determinism is solid (seeded LCG noise, pure sines, no timing/async). AudioLevel and ToneOscillator suites are exemplary — boundary, monotonicity, and property-sweep style assertions.
- The `assertFrequency` helper is duplicated verbatim across MPMTests and YINTests with different `Estimate`/`PitchEstimate` types; acceptable but a shared generic helper would reduce drift.
- Tolerances are inconsistent and mostly *loose*: octave tests allow 8 cents, bass 10–12 cents. For pure synthetic sines the detectors should hit ~1–2 cents; loose tolerances hide regressions in the parabolic refinement (`MPM.swift:264`, `YIN.swift:133`).
- Comments occasionally describe behavior the test does not actually assert (e.g. the −45 dB comment; the "boosts clarity" test that the clamp makes vacuous). Comment/assertion drift is a maintenance hazard here.
- `SignalGenerators` is the leverage point: adding `decayingTone`, `inharmonicTone`, and `toneInNoise` builders would unlock most of the missing realistic coverage cheaply.

## Top 3 priorities

1. **Add realistic low-string detection tests** (new fixtures + cases): weak-fundamental/harmonic-dominant 82 Hz & 41 Hz, inharmonic partials, decaying envelopes, and tone-in-hum — run through MPM, YIN, ensemble, and the full `MPMPitchDetector.process` with the preprocessor on. This is where real flakiness lives and where the suite is blind.
2. **Cover the ensemble disagreement & single-fire branches** and make `test_ensemble_corroboration` non-vacuous (assert the +0.1 boost on a mid-clarity input, strictly greater) so octave-recovery logic is actually verified.
3. **Pin the gates and the preprocessor's purpose:** boundary pairs for the −52 dB level gate (fix the wrong −45 dB comment/bug) and 0.6 clarity gate, plus a filtered-vs-unfiltered detection comparison proving the band-pass helps a weak low E (and tests for filter statefulness/reset across buffers).
