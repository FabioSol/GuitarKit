//
//  CapoControlView.swift
//  GuitarKit
//
//  The quiet "Capo" chip that sits on the Tuner face (PRD story 24). It's a
//  small, low-chrome control — deliberately NOT a hero — that lets the player
//  clamp a virtual capo across the neck, shifting every string target up by N
//  semitones.
//
//  BEHAVIOUR (from the PRD + issue #11):
//    • Resting (fret 0): a quiet pill with just a capo icon + the word "Capo".
//    • Engaged (fret > 0): the pill shows the "+N" counter AND a small clear/
//      delete icon to reset back to 0.
//    • Tapping the pill INCREMENTS by one fret. We CLAMP at 12 (stop, don't
//      wrap) — see note on `onIncrement` below for why "stop" was chosen.
//    • The clear icon (and a long-press as a secondary gesture) RESETS to 0.
//    • The whole pill is one VoiceOver element that is ADJUSTABLE: swiping up
//      raises the capo, swiping down lowers it, and VoiceOver speaks
//      "Capo on fret 2".
//
//  PRESENTATIONAL ONLY — NO STATE HERE:
//  This view does not own the capo value. It receives an immutable `capo` to
//  render and two callbacks (`onIncrement`, `onReset`) to report intent. The
//  TuningSessionModel owns the real `Capo`, applies the clamp, and rebuilds the
//  string targets. Keeping the view "dumb" means all the musical truth lives in
//  one tested place and this file is purely about look + gestures.
//

import SwiftUI

struct CapoControlView: View {

    // MARK: Inputs

    /// The capo to render. Already clamped 0...12 by the `Capo` type itself, so
    /// this view never has to validate it — it just reflects it.
    let capo: Capo

    /// Called when the player wants to raise the capo by one fret (a tap, or a
    /// VoiceOver "increment" swipe). The OWNER decides what "increment" means and
    /// applies the clamp; this view only reports the intent.
    ///
    /// WHY THE OWNER CLAMPS, NOT US: the `Capo` initializer already clamps to
    /// 0...12, and the model is where the value lives, so letting the model add
    /// `+1` and re-wrap through `Capo(fret:)` keeps "stop at 12" as one rule in
    /// one place. (We picked STOP-at-12 over wrap-to-0: wrapping would let a
    /// stray extra tap silently throw away a carefully set capo, which feels
    /// worse than a tap that simply does nothing at the ceiling.)
    let onIncrement: () -> Void

    /// Called when the player wants to LOWER the capo by one fret — the symmetric
    /// partner to `onIncrement`, fired by a VoiceOver "decrement" swipe. The owner
    /// applies the 0...12 clamp, so swiping down at fret 0 is a harmless no-op.
    let onDecrement: () -> Void

    /// Called when the player wants to clear the capo back to fret 0 — fired by
    /// the delete icon or by a long-press anywhere on the pill.
    let onReset: () -> Void

    // MARK: Body

    var body: some View {
        // The visible pill. We branch its CONTENT on whether a capo is engaged,
        // but keep it a single accessibility element (see the modifiers at the
        // bottom) so VoiceOver treats the whole thing as one adjustable control
        // rather than several separate buttons.
        HStack(spacing: 6) {
            // A capo always shows its icon — a guitar-ish glyph. SF Symbols
            // doesn't ship a literal "capo", so we use "guitars" as a recognisable
            // stand-in for "fretboard / clamp" context.
            Image(systemName: "guitars")
                .font(.footnote)

            if let badge = CapoLabel.badge(for: capo) {
                // ENGAGED: show the "+N" counter in steady tabular digits so the
                // pill doesn't visibly resize as the number changes width.
                Text(badge)
                    .font(GKFont.caption)
                    .tabularNumbers()

                // The clear/delete affordance. It's a *visual* cue inside the
                // single accessibility element (we hide it from VoiceOver and
                // expose "reset" instead via the adjustable action + a custom
                // action, so blind users aren't hunting for a tiny x).
                Image(systemName: "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(GKColor.textSecondary)
                    // Let sighted users tap the x directly to clear. This MUST be a
                    // `.highPriorityGesture` (not a plain `.onTapGesture`): the pill
                    // underneath has its own increment tap, and SwiftUI's resolution
                    // of an inner vs. outer *plain* tap is hit-test/order dependent —
                    // so a plain inner tap could lose and INCREMENT instead of clear.
                    // `highPriorityGesture` guarantees the x wins on its own area.
                    .highPriorityGesture(TapGesture().onEnded { onReset() })
                    .accessibilityHidden(true)
            } else {
                // RESTING: just the quiet word "Capo", no counter, no x.
                Text("Capo")
                    .font(GKFont.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // The pill's fill + tint shift to signal active vs resting WITHOUT
        // relying on color alone (the "+N" text and the x icon are the primary
        // non-color cues; this tint just reinforces them). Engaged = a soft
        // accent wash; resting = a neutral secondary wash.
        .background {
            Capsule()
                .fill(capo.isEngaged
                      ? GKColor.accent.opacity(0.18)
                      : GKColor.textSecondary.opacity(0.12))
        }
        .foregroundStyle(capo.isEngaged ? GKColor.accent : GKColor.textSecondary)
        // A primary tap anywhere on the pill raises the capo by one fret.
        .onTapGesture { onIncrement() }
        // A long-press is the secondary "clear everything" gesture, matching the
        // PRD's "delete/clear" intent for people who'd rather not aim for the x.
        .onLongPressGesture { onReset() }

        // MARK: Accessibility — one adjustable element
        //
        // We collapse the pill into a SINGLE element so VoiceOver announces it
        // as one control, then make it ADJUSTABLE: with focus on it, a VoiceOver
        // user swipes up to raise the capo and down to lower it. This is the
        // standard "stepper-like" pattern and is exactly what the PRD asks for
        // ("exposed as a VoiceOver-adjustable element").
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CapoLabel.accessibility(for: capo))
        // Hint tells first-time users HOW to change it (VoiceOver reads this
        // after a short pause).
        .accessibilityHint("Swipe up or down to change the capo fret")
        .accessibilityAdjustableAction { direction in
            // VoiceOver hands us a direction; we translate it to our callbacks.
            // The owner applies the 0...12 clamp, so swiping past either end is
            // harmless (it just no-ops at the boundary).
            switch direction {
            case .increment: onIncrement()
            case .decrement:
                // Step DOWN one fret — symmetric with increment. (Previously this
                // jumped straight to reset, so one down-swipe on a capo at fret 5
                // landed on 0 and announced "No capo", which reads as a bug to a
                // VoiceOver user expecting ±1 steps.) The explicit clear lives on
                // the x and the long-press; the owner clamps so fret 0 no-ops.
                onDecrement()
            @unknown default:
                // `accessibilityAdjustableAction`'s direction is a frozen-ish
                // system enum; this arm future-proofs us against new cases.
                break
            }
        }
    }
}

// MARK: - Preview

#Preview {
    // A tiny stateful wrapper so the preview's taps actually move the capo,
    // letting us feel the resting → engaged → cleared transitions live.
    struct PreviewHost: View {
        @State private var capo = Capo.none
        var body: some View {
            VStack(spacing: 24) {
                CapoControlView(
                    capo: capo,
                    onIncrement: { capo = Capo(fret: capo.fret + 1) },
                    onDecrement: { capo = Capo(fret: capo.fret - 1) },
                    onReset: { capo = .none }
                )
                Text("fret = \(capo.fret)")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
            }
            .padding()
            .background(GKColor.background)
        }
    }
    return PreviewHost()
}
