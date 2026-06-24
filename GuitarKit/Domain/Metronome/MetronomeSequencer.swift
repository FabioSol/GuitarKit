//
//  MetronomeSequencer.swift
//  GuitarKit
//
//  The PURE beat-timing math behind the metronome. No AVFoundation, no audio
//  hardware, no UI — just "given a tempo and a sample rate, at exactly which
//  sample does beat N happen?" That separation is deliberate (same idea as
//  `AudioLevel`/`ToneOscillator`): this is the part we can unit-test
//  deterministically — feed in a BPM and assert the beats land where they should
//  and never drift — while the noisy real-time playback lives in
//  `MetronomeEngine`.
//
//  WHY MEASURE TIME IN *SAMPLES* INSTEAD OF SECONDS?
//  Digital audio is a long list of numbers ("samples") played back at a fixed
//  rate (the SAMPLE RATE, e.g. 44 100 samples per second). The audio hardware
//  advances through those samples on its own rock-steady clock. If we tell it
//  "play this click at sample number 22 050", it plays it at *exactly* that
//  instant — far more precise than asking a software `Timer` to fire "every
//  0.5 seconds" (a `Timer` is at the mercy of the main run loop and drifts a
//  little every beat, so over a few minutes the metronome wanders off the beat).
//  So the whole metronome is built around scheduling clicks at integer SAMPLE
//  OFFSETS. This struct computes those offsets.
//
//  THE DRIFT-FREE TRICK (the important part):
//  One beat lasts `samplesPerBeat` samples — usually NOT a whole number (e.g.
//  120 BPM @ 44.1 kHz = 22 050.0, but 130 BPM = 20 353.846…). If we computed
//  each beat by *adding* a rounded integer step to the previous one, the tiny
//  rounding error (a fraction of a sample) would accumulate beat after beat and
//  the metronome would slowly drift — exactly what we're trying to avoid.
//
//  Instead we compute every beat's position from beat 0 in floating point and
//  round only at the very end:
//
//      offset(beat n) = round(n · samplesPerBeat)
//
//  Because each offset is derived independently from the exact (un-rounded)
//  beat spacing, the rounding error never compounds — it stays within ±0.5 of
//  a sample forever, no matter how many beats play. That's the essence of
//  "drift-free", and it's what the tests assert.
//

import Foundation

/// A namespace (empty `enum`, the same trick as `AudioLevel`/`ToneOscillator`)
/// bundling the pure metronome-timing math. Callers write
/// `MetronomeSequencer.samplesPerBeat(...)` etc. Marked `enum` with no cases so
/// it can never be instantiated — it's just a home for these `static` functions.
enum MetronomeSequencer {

    // MARK: - Beat spacing

    /// How many output samples make up ONE beat at a given tempo.
    ///
    /// A "beat" is one tick of the metronome. Tempo is in BPM (beats per
    /// minute), so:
    ///
    ///     seconds per beat = 60 / bpm
    ///     samples per beat = (60 / bpm) · sampleRate
    ///
    /// For example at 120 BPM and 44 100 Hz: (60 / 120) · 44 100 = 0.5 · 44 100
    /// = 22 050 samples between clicks.
    ///
    /// We return a `Double` (not an `Int`) ON PURPOSE: the exact spacing is
    /// usually fractional, and keeping the fraction is what makes the rounding
    /// in `sampleOffset(ofBeat:...)` drift-free. Rounding here would throw the
    /// precision away too early.
    ///
    /// - Parameters:
    ///   - bpm: tempo in beats per minute. Must be > 0.
    ///   - sampleRate: output samples per second (e.g. 44 100). Must be > 0.
    /// - Returns: the exact (possibly fractional) number of samples per beat,
    ///   or `0` if either input is non-positive (a defensive "no tempo").
    static func samplesPerBeat(bpm: Double, sampleRate: Double) -> Double {
        // Guard against non-positive inputs so we never divide by zero or hand
        // back a negative/garbage spacing. A bad tempo simply means "no beats".
        guard bpm > 0, sampleRate > 0 else { return 0 }
        return (60.0 / bpm) * sampleRate
    }

    // MARK: - Absolute beat positions (the drift-free part)

    /// The absolute sample offset of beat number `beat`, measured from beat 0.
    ///
    /// This is the heart of the drift-free design. Rather than stepping forward
    /// one beat at a time (which would accumulate rounding error), we multiply
    /// the EXACT fractional beat spacing by the beat index and round ONCE:
    ///
    ///     offset(beat n) = round(n · samplesPerBeat)
    ///
    /// Beat 0 is therefore always sample 0 (round(0) = 0). Every later beat is
    /// computed independently from beat 0, so the rounding error per beat never
    /// exceeds half a sample and — crucially — never compounds. Over thousands
    /// of beats the spacing stays within ±1 sample of the ideal, which the
    /// tests verify.
    ///
    /// We return an `Int` because the audio system schedules at whole-sample
    /// positions (you can't play "half a sample" early).
    ///
    /// - Parameters:
    ///   - beat: which beat (0 = the first/downbeat, 1 = the next, …). Negative
    ///     values are clamped to 0 — there's no beat before the start.
    ///   - bpm: tempo in beats per minute. Must be > 0.
    ///   - sampleRate: output samples per second. Must be > 0.
    /// - Returns: the integer sample offset (from beat 0) at which this beat
    ///   should sound; `0` for invalid tempo/sample-rate.
    static func sampleOffset(ofBeat beat: Int, bpm: Double, sampleRate: Double) -> Int {
        // No such thing as a beat before the first one.
        guard beat > 0 else { return 0 }

        let spacing = samplesPerBeat(bpm: bpm, sampleRate: sampleRate)
        // `samplesPerBeat` already guards bad inputs and returns 0; surface that
        // as offset 0 too rather than producing a meaningless position.
        guard spacing > 0 else { return 0 }

        // The whole trick in one line: multiply the EXACT spacing by the beat
        // index, then round to the nearest whole sample. Because `beat` and
        // `spacing` are recombined from scratch each call, the error can't pile
        // up across beats. `.rounded()` rounds to the nearest integer (.5 away
        // from zero); `Int(...)` then drops the now-whole fractional part.
        return Int((Double(beat) * spacing).rounded())
    }

    // MARK: - Pre-scheduling helper

    /// Produce the sample offsets of the next `count` beats, starting at
    /// `firstBeat`. This is what the engine uses to PRE-SCHEDULE a rolling
    /// window of upcoming clicks in one go.
    ///
    /// The metronome never relies on wall-clock time to decide when to play.
    /// Instead it hands the audio system a batch of "play a click at sample X,
    /// another at sample Y, …" instructions up front, then tops the batch up as
    /// beats are consumed. This helper computes that batch of absolute offsets.
    ///
    /// Each offset is still computed via `sampleOffset(ofBeat:...)`, so the
    /// whole list inherits the drift-free property — every entry is anchored to
    /// beat 0, not to its predecessor.
    ///
    /// Example: `offsets(fromBeat: 4, count: 3, bpm: 120, sampleRate: 44100)`
    /// returns the offsets of beats 4, 5 and 6.
    ///
    /// - Parameters:
    ///   - firstBeat: the index of the first beat to include (0-based).
    ///   - count: how many consecutive beats to emit. `<= 0` → an empty array.
    ///   - bpm: tempo in beats per minute. Must be > 0.
    ///   - sampleRate: output samples per second. Must be > 0.
    /// - Returns: `count` ascending integer sample offsets (one per beat),
    ///   or an empty array for non-positive `count` / invalid tempo.
    static func offsets(
        fromBeat firstBeat: Int,
        count: Int,
        bpm: Double,
        sampleRate: Double
    ) -> [Int] {
        // Nothing to schedule.
        guard count > 0 else { return [] }

        // `map` over the beat indices firstBeat ..< firstBeat+count, turning
        // each beat number into its absolute sample offset. Clamp a negative
        // starting beat up to 0 so we never ask for a pre-start beat.
        let start = max(firstBeat, 0)
        return (start..<(start + count)).map { beat in
            sampleOffset(ofBeat: beat, bpm: bpm, sampleRate: sampleRate)
        }
    }

    // MARK: - Subdivision ("tick") spacing — drift-free at the sub-beat level
    //
    // A SUBDIVISION chops each beat into smaller, evenly-spaced pulses we call
    // "ticks." With `ticksPerBeat` ticks per beat (quarter = 1, eighth = 2,
    // triplet = 3, sixteenth = 4), tick 0 is beat 0, and every `ticksPerBeat`-th
    // tick lands exactly on a beat. The math below mirrors the beat math one
    // level finer — and stays drift-free for the SAME reason: every tick's
    // position is computed independently from tick 0, never by adding to the
    // previous tick, so rounding error can't accumulate.

    /// How many output samples make up ONE tick at a given tempo and
    /// subdivision. A tick is a fraction of a beat:
    ///
    ///     samplesPerTick = samplesPerBeat / ticksPerBeat
    ///
    /// We keep this fractional (a `Double`) for exactly the same reason as
    /// `samplesPerBeat`: rounding here would throw away the precision that makes
    /// `tickOffset(ofTick:...)` drift-free.
    ///
    /// - Parameters:
    ///   - bpm: tempo in beats per minute. Must be > 0.
    ///   - sampleRate: output samples per second. Must be > 0.
    ///   - ticksPerBeat: how many ticks divide one beat (≥ 1). Values < 1 are
    ///     treated as 1 (a tick == a beat) so we never divide by zero.
    /// - Returns: the exact (possibly fractional) samples per tick, or `0` for
    ///   invalid tempo/sample-rate.
    static func samplesPerTick(bpm: Double, sampleRate: Double, ticksPerBeat: Int) -> Double {
        let perBeat = samplesPerBeat(bpm: bpm, sampleRate: sampleRate)
        // `samplesPerBeat` already returns 0 for bad inputs; pass that through.
        guard perBeat > 0 else { return 0 }
        // Guard the divisor: a non-positive tick count collapses to "1 tick per
        // beat" (i.e. ticks == beats) rather than dividing by zero.
        let divisor = max(ticksPerBeat, 1)
        return perBeat / Double(divisor)
    }

    /// The absolute sample offset of tick number `tick`, measured from tick 0.
    ///
    /// This is the sub-beat sibling of `sampleOffset(ofBeat:...)`, and it stays
    /// drift-free the same way — multiply the EXACT fractional tick spacing by
    /// the tick index and round ONCE:
    ///
    ///     offset(tick n) = round(n · samplesPerTick)
    ///
    /// Because every `ticksPerBeat`-th tick reuses the same exact spacing, ticks
    /// that fall on a beat line up with the beat math, and the clicks between
    /// beats are perfectly even. Tick 0 is always sample 0.
    ///
    /// - Parameters:
    ///   - tick: which tick (0 = the first/downbeat). Negatives clamp to 0.
    ///   - bpm: tempo in beats per minute. Must be > 0.
    ///   - sampleRate: output samples per second. Must be > 0.
    ///   - ticksPerBeat: how many ticks divide one beat (≥ 1).
    /// - Returns: the integer sample offset (from tick 0) of this tick; `0` for
    ///   invalid tempo/sample-rate or a non-positive tick index.
    static func tickOffset(ofTick tick: Int, bpm: Double, sampleRate: Double, ticksPerBeat: Int) -> Int {
        // No tick before the first one.
        guard tick > 0 else { return 0 }

        let spacing = samplesPerTick(bpm: bpm, sampleRate: sampleRate, ticksPerBeat: ticksPerBeat)
        guard spacing > 0 else { return 0 }

        // Same one-line drift-free trick as the beat version, one level finer.
        return Int((Double(tick) * spacing).rounded())
    }

    /// Produce the sample offsets of the next `count` TICKS, starting at
    /// `firstTick`. The tick-level analogue of `offsets(fromBeat:count:...)`,
    /// used by the engine to pre-schedule a rolling window of sub-beat clicks.
    ///
    /// Every entry is computed via `tickOffset(ofTick:...)`, so the whole batch
    /// inherits the drift-free property — anchored to tick 0, never to the
    /// previous tick.
    ///
    /// - Parameters:
    ///   - firstTick: index of the first tick to include (0-based).
    ///   - count: how many consecutive ticks to emit. `<= 0` → empty array.
    ///   - bpm: tempo in beats per minute. Must be > 0.
    ///   - sampleRate: output samples per second. Must be > 0.
    ///   - ticksPerBeat: how many ticks divide one beat (≥ 1).
    /// - Returns: `count` ascending integer sample offsets (one per tick), or
    ///   an empty array for non-positive `count` / invalid tempo.
    static func tickOffsets(
        fromTick firstTick: Int,
        count: Int,
        bpm: Double,
        sampleRate: Double,
        ticksPerBeat: Int
    ) -> [Int] {
        guard count > 0 else { return [] }
        let start = max(firstTick, 0)
        return (start..<(start + count)).map { tick in
            tickOffset(ofTick: tick, bpm: bpm, sampleRate: sampleRate, ticksPerBeat: ticksPerBeat)
        }
    }
}
