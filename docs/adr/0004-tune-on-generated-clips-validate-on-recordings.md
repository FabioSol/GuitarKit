# Detection parameters are searched on generated clips and validated on real recordings

Detection parameters (thresholds, the probabilistic model's probabilities) are chosen by searching (`PitchBench/tune.py`, Optuna) on *generated* clips — plucked strings under synthesized interference — then ranked on a held-out set of generated clips and checked against real recordings the search never sees. Recordings are too few to tune on without memorizing them; generated clips are plentiful but too clean.

## Consequences

- The search exploits whatever the generator gets wrong. Twice it did: it picked HPS (which can't hear pure tones) until a clean-tones guard was added, and it pushed the harmonicity gate to ~0.9 because generated strings score ~0.93 while real ones score ~0.86. Ranges that depend on realism are capped at what real recordings show.
- A pick must detect at least as well as the current defaults, including on soft plucks, before fewer wrong readings count — otherwise "show nothing" wins, since silence is never wrong.
- Real recordings are the final word; a result that holds on generated clips but not on recordings is a generator artifact.
