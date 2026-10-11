---
status: proposed
---

# Targeted mode tracks strings with a probabilistic model

Per-frame gates (clarity, level, harmonicity) can't tell a guitar string from a voice or a held keyboard note — both are loud, clear and pitched — and they force hard plucks, because only the loudest frames clear them. `StringStateTracker` instead keeps a running belief over "which string, if any, is ringing" (a hidden Markov model run forward each frame): evidence builds up across frames, strings mostly start on a pluck, hold their pitch, sit near their target, and stay tracked underneath a voice while their own partials still stand out. On real recordings it doubled coverage and cut wrong readings from 18% to 6% versus the gated engine.

Chromatic mode keeps the gated engine: with no tuning there are no strings to track, and it must name any sound.

## Consequences

Status is *proposed* until it has been tried live on a phone; the app still defaults to the gated engine and the Tuner Lab switches between them. Its parameters come from a search (ADR 0004), so changing them by hand without re-running the benchmark undoes that evidence.
