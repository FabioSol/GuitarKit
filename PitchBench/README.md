# PitchBench

A measuring stick for the tuner's pitch tracking. Real recordings of your
guitar are replayed through `PitchTracker` exactly the way the live tuner feeds
it, and every change to the pipeline gets a number instead of a feeling.

- `recordings/` — labelled clips (`.wav` + `.json` pairs) made with the Tuner Lab.
- `RESULTS.md` — the latest scores, written by `PitchBenchmarkTests`. Commit it,
  so `git diff PitchBench/RESULTS.md` shows what a change actually did.

## 1. Record clips (on your iPhone, Debug build)

1. Run the app from Xcode on your phone, open the Tuner, tap the flask (Tuner Lab).
2. In **Benchmark clips**, pick the **String**, how hard you'll **Pluck**, and the
   **Background** noise in the room. Leave **Length** at 6 s.
3. Tap **Record clip**, pluck the string **once**, and let it ring. The clip
   saves itself when the time is up.
4. For noise-only clips, choose **Noise only** and don't touch the guitar.

A useful first set (~25 clips, ten minutes):

| what | how many |
|---|---|
| every string, **soft** pluck, quiet room | 6 |
| every string, **medium** pluck, quiet room | 6 |
| every string, **hard** pluck, quiet room | 6 |
| low E, A and high E, **soft**, with each background below | 3 per background |
| **noise only** — each background, nothing plucked | 1 per background |

Backgrounds, roughly from easiest to hardest for the tracker:

| background | examples |
|---|---|
| quiet | an ordinary quiet room |
| fan | fan, AC, traffic rumble — steady, no pitch |
| clicks | typing, tapping, setting a cup down |
| talking | people talking nearby |
| instruments | someone else playing — another guitar is the hardest |
| video | a phone or TV playing a video (speech + music) |

Hold the phone where you normally would when tuning. Soft plucks matter most:
that's the case the tuner struggles with today.

## 2. Bring them to the Mac

In the Lab, tap **Share N clips** → AirDrop to your Mac, then move every
`.wav` **and** `.json` into `PitchBench/recordings/`. A clip without its
`.json` can't be scored.

## 3. Run the benchmark

The fast way (about 30 s; builds the real pitch code as an optimized Mac tool,
no simulator needed):

```sh
PitchBench/run.sh
```

Or inside the iOS test suite — slower (minutes, because Debug builds are
unoptimized), so ⌘U skips it unless `PITCH_BENCH=1` is set:

```sh
TEST_RUNNER_PITCH_BENCH=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test -scheme GuitarKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:GuitarKitTests/PitchBenchmarkTests
```

Then open `RESULTS.md`. The summary table has one row per background and one
column per pluck strength — compare **soft** with **hard** to see how much the
tuner depends on the attack, and read down a column to see which backgrounds
throw it off. The **Nothing plucked** table shows what each background makes
the tuner display on its own (ideally nothing).

## Generated clips

Before any recording exists, the benchmark also generates clips: 4 strings ×
3 pluck strengths under each kind of interference at two levels (−55 dBFS,
quieter than a soft pluck, and −40 dBFS, as loud or louder), plus each
background on its own. The interference is synthesized in
`GuitarKitTests/Pitch/Benchmark/Interference.swift` — steady rumble and fan
noise, another guitar, keyboard chords, speech (gliding pitch in the low
strings' range), clicks and knocks, and a phone playing a video. Generated
clips can't replace real ones, but they're deterministic, so a change to the
tracker moves their numbers and nothing else does.

## What the columns mean

| column | meaning | good |
|---|---|---|
| detected | the right note (±50¢) showed up at all | all ✓ |
| latency | note audible → first correct reading | low |
| coverage | share of the audible note with a correct reading on screen (— = the string was never louder than the background) | high |
| sustain | seconds of correct readings | high |
| jitter | mean jump between consecutive readings, in cents | low |
| median ¢ | where the string actually sat — a real string is rarely exactly in tune | (info) |
| wrong | readings more than 50¢ off the plucked note — usually the tracker following the background | 0 |
| false | seconds of readings on a noise-only clip | 0 |

## Tuning the parameters (Optuna)

`tune.py` searches every tracker knob (algorithm, gates, smoothing, the
note-continuity rules, the band margins) for the best trade-off between three
goals: **coverage ↑**, **wrong readings ↓**, and **false readings ↓**.

```sh
uv run --with optuna PitchBench/tune.py --trials 600 --jobs 6
```

About 5–10 minutes. It runs several `run.sh serve` processes in parallel and
writes `TUNING.md` (the report) and `tuning/recommended.json` (the best
settings). Re-running continues the same study.

**How it avoids fooling itself:** the search only ever sees the generated
*train* clips. The best candidates are then ranked on the generated *test*
clips (same conditions, different random details) and checked against your
real recordings — neither of which the search saw. If a pick is great on
train but not on test or recorded, it learned the generator, not guitars.
Nothing in the app changes until you adopt the settings yourself.

## The harmonic check

In targeted mode, after the detector names a pitch, the tracker asks how much
of the sound sits on that pitch's harmonic series (`HPS.harmonicity`). A
plucked string — or a pure tone — is one harmonic source and scores high; a
voice (gliding harmonics), a chord (other notes' energy), clicks and noise
score lower. Frames below the gate can't start a note (a tracked note's tail
gets a looser threshold). Chromatic mode and capture-while-editing turn it off.

The gate (`PitchTrackerConfig.targetedModeHarmonicGate`, 0.65) was chosen from
a sweep on the real recordings, **not** by the parameter search: generated
strings are too clean (they score ~0.93; real ones ~0.86 with a long tail), so
a search on generated clips pushes the gate to ~0.9 — which on real audio
throws away 99% of string frames. `tune.py` caps the gate at 0.75 for that
reason. With only six recordings, treat 0.65 as provisional: more recordings
(especially soft plucks and other backgrounds) should confirm or move it. The
Tuner Lab has a slider to try other values live.

## The probabilistic engine

`StringStateTracker` (targeted mode) keeps a running belief about which string
— if any — is ringing, instead of judging each frame on its own. Evidence
builds up across frames: harmonicity, distance to each string's target, pitch
stability (strings hold steady, voices glide), and whether a string's own
partials still stand out in the spectrum even when the detector has latched
onto a voice. Strings almost only start on a pluck (a level jump).

Its parameters come from an Optuna search (`tune.py --space probabilistic
--study hmm`, report in `TUNING-hmm.md`), with the harmonicity midpoint capped
at real strings' 25th percentile so the search can't learn the generator.
`run.sh` writes `RESULTS-probabilistic.md` next to `RESULTS.md` so the two
engines can be compared clip by clip. The app still defaults to the gated
engine; switch in the Tuner Lab (Detection — engine).
