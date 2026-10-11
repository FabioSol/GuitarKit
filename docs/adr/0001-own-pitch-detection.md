# Pitch detection is our own code, not AudioKit or SwiftF0

We keep our own DSP (MPM/YIN with harmonic checks, behind `PitchTracker`) instead of adopting a library. AudioKit's `PitchTap` (Soundpipe `ptrack`) reports no confidence score, which the tracker needs to reject interference; SwiftF0 is a neural model whose output bins are ~33 cents wide, was only evaluated to ±50 cents (a tuner needs ±1), bottoms out at 46.9 Hz (missing bass low E and B), and ships as ONNX only. Either would replace only the "estimate a pitch" step — the guitar-specific logic around it (bands, gates, string tracking) would remain ours anyway.

## Consequences

Detection quality is ours to measure: every change to it is judged with `PitchBench/` (see ADR 0004). A neural model may still earn a place later as one vote among several, if recordings show note-identity errors the DSP can't fix.
