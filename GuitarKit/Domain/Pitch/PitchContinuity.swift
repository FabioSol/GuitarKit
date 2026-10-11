//
//  PitchContinuity.swift
//  GuitarKit
//
//  The TEMPORAL hygiene stage between the per-buffer gates and the smoother.
//  The gates (level, clarity) judge each buffer in isolation; this filter
//  judges the STREAM — because a real note and background noise look different
//  over consecutive frames even when a single frame can fool the gates.
//
//  THE TWO FAILURE MODES IT FIXES (seen on an unamplified electric guitar,
//  where the decay tail sits barely above the room's noise floor):
//
//   1. STALE HISTORY ACROSS SILENCES. Only the level gate used to reset the
//      smoother; the detect-failed / clarity-failed paths kept its history. With
//      a sensitive level gate the gate rarely closed, so a stray noise frame
//      accepted during a between-plucks gap landed in a median window still
//      holding the previous note — flipping the displayed pitch around wildly.
//      → After `dropoutFrames` CONSECUTIVE rejections we declare a dropout, and
//        the caller drops its smoothing history. One flickered frame mid-note
//        (streak below the limit) keeps history, so a sustained note isn't
//        punished for a single marginal buffer.
//
//   2. ISOLATED FALSE ACCEPTS. Noise occasionally looks periodic enough to pass
//      the clarity gate for ONE frame — and one frame used to reach the screen
//      and the tuning session (hopping the active string, resetting hold timers).
//      → After a dropout, the first accepted estimate is held back as an
//        unconfirmed CANDIDATE. It is published only when the NEXT frame agrees
//        with it (within `agreementCents`). Random noise estimates almost never
//        agree with themselves twice in a row; a real string trivially does.
//        Cost: one buffer (~93 ms) of latency on note ONSET only — invisible
//        next to the 0.7 s hold-to-latch.
//
//   3. THE TAIL DYING EARLY (onset/sustain HYSTERESIS). Deciding a note STARTED
//      and deciding it's STILL GOING are different hypothesis tests: at onset
//      we know nothing, so evidence must be strict; mid-note we know a note is
//      ringing AND its pitch, so a marginal frame NEAR that pitch is almost
//      certainly the decaying tail, not noise. Frames therefore arrive in two
//      grades: `.strong` (passed the onset gates) and `.weak` (passed only the
//      detector's relaxed sustain gates).
//      → `.strong` frames behave as before: they alone can start/confirm a note.
//      → `.weak` frames count ONLY while tracking, and only within
//        `agreementCents` of the last tracked pitch — they extend the note (the
//        needle lives through the tail) but can never start one. While dormant
//        they're rejected like any noise, so onset strictness is untouched.
//
//  Pure value logic (a tiny state machine): frame verdicts in, verdicts out.
//  No clocks, no audio — fully unit-testable with scripted sequences.
//

import Foundation

/// Tracks accept/reject continuity across detection frames and decides, per
/// frame, whether an estimate is trustworthy enough to smooth + display.
///
/// A `struct` with `mutating` methods, like `PitchSmoother`: a little state,
/// no identity. The detector owns one instance and feeds it every frame.
nonisolated struct PitchContinuity {

    // MARK: Configuration

    /// How many CONSECUTIVE rejected frames end the current note (a "dropout").
    /// 2 frames ≈ 190 ms at our buffer cadence: long enough to ride out one
    /// marginal buffer mid-note, short enough that history never bridges a
    /// real silence between plucks.
    let dropoutFrames: Int

    /// How closely (in cents) two frequencies must agree to count as "the same
    /// pitch" — used both to confirm a new onset (two consecutive frames) and
    /// to accept a weak frame against the tracked pitch. 100¢ (a semitone) is
    /// deliberately loose — it only has to separate "same note" from "two
    /// random noise pitches".
    let agreementCents: Float

    // MARK: State

    /// Consecutive rejected frames so far (0 while estimates are flowing).
    private var rejectStreak = 0

    /// The first accepted estimate after a dropout, awaiting confirmation by
    /// the next frame. `nil` when tracking or when nothing is pending.
    private var candidate: Float?

    /// Whether we're inside a CONFIRMED note — estimates flow straight through
    /// until a dropout ends it.
    private var isTracking = false

    /// The most recently tracked frequency — the anchor a `.weak` frame must
    /// sit near to count as the tail of the current note.
    private var lastTracked: Float?

    /// Whether a confirmed note is in progress. The detector reads this to
    /// decide if a below-onset-level buffer is even worth analyzing (a weak
    /// frame can only matter while tracking).
    var isTrackingNote: Bool { isTracking }

    init(dropoutFrames: Int = 2, agreementCents: Float = 100) {
        self.dropoutFrames = dropoutFrames
        self.agreementCents = agreementCents
    }

    // MARK: Frames

    /// One frame's graded evidence, as judged by the detector's gates.
    enum Frame: Equatable {
        /// Passed the strict ONSET gates — may start, confirm, or extend a note.
        case strong(Float)
        /// Passed only the relaxed SUSTAIN gates — may extend a tracked note
        /// (near its pitch), never start one.
        case weak(Float)
    }

    // MARK: Verdicts

    /// What the caller should do with this frame.
    enum Verdict: Equatable {
        /// Trust these frequencies, in order — push them through smoothing and
        /// publish. One entry mid-note; two on onset confirmation (the held
        /// candidate first, then the confirming frame, so the smoother starts
        /// with both real observations).
        case track([Float])
        /// An unconfirmed candidate is pending — publish nothing this frame.
        case hold
        /// Rejected frame, but within the streak allowance — publish nothing,
        /// keep smoothing history.
        case silence
        /// The reject streak just hit the limit — publish nothing AND drop
        /// smoothing history (fires once per dropout, on the edge).
        case dropout
    }

    // MARK: The per-frame step

    /// Advance with this frame's graded evidence, or `nil` if the frame was
    /// rejected by every gate (level / no-estimate / clarity).
    mutating func ingest(_ frame: Frame?) -> Verdict {
        switch frame {
        case .strong(let frequency) where frequency > 0:
            rejectStreak = 0

            // Mid-note: confirmed already, estimates flow straight through.
            if isTracking {
                lastTracked = frequency
                return .track([frequency])
            }

            // Onset: does this frame confirm the pending candidate?
            if let pending = candidate, centsApart(pending, frequency) <= agreementCents {
                candidate = nil
                isTracking = true
                lastTracked = frequency
                return .track([pending, frequency])
            }

            // No candidate (or it disagreed): this frame BECOMES the candidate.
            // A disagreeing pair means at least one of the two was junk — the
            // newer frame is the better bet for the next comparison.
            candidate = frequency
            return .hold

        case .weak(let frequency) where frequency > 0:
            // A weak frame is only believable as the TAIL of the note we're
            // already tracking — i.e. near the tracked pitch. Anywhere else
            // (dormant, or far from the anchor) it's noise: reject it. Note it
            // can never confirm a candidate — onset demands strong evidence.
            if isTracking, let anchor = lastTracked,
               centsApart(anchor, frequency) <= agreementCents {
                rejectStreak = 0
                lastTracked = frequency
                return .track([frequency])
            }
            return reject()

        default:
            return reject()
        }
    }

    /// The shared rejected-frame path: a pending candidate dies (confirmation
    /// requires CONSECUTIVE agreement), and a long-enough streak ends the note.
    private mutating func reject() -> Verdict {
        candidate = nil
        rejectStreak += 1
        if isTracking && rejectStreak >= dropoutFrames {
            // The note just ended: signal the (one-shot) history drop.
            isTracking = false
            return .dropout
        }
        return .silence
    }

    /// Forget everything — call alongside a smoother reset (audio stopped,
    /// detection band changed) so the next note starts from scratch.
    mutating func reset() {
        rejectStreak = 0
        candidate = nil
        isTracking = false
        lastTracked = nil
    }

    /// Absolute distance between two frequencies, in cents.
    private func centsApart(_ a: Float, _ b: Float) -> Float {
        abs(1200 * log2(a / b))
    }
}
