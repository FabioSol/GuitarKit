//
//  TunerHeroView.swift
//  GuitarKit
//
//  The Tuner's hero screen for targeted tuning: the headstock up top, the linear
//  cents meter below it, a gentle "next string" nudge, and a restrained
//  completion flourish when every string is in tune. Replaces the placeholder
//  `TuningSessionView` from slice #05 — same underlying `TuningSessionModel`,
//  now wearing its real face.
//

import SwiftUI

struct TunerHeroView: View {

    /// The session model (observable). Reading its properties here is what makes
    /// the view re-render as tuning progresses.
    let model: TuningSessionModel

    /// Reduce Motion → the completion flourish degrades to a plain state change
    /// (no scale/glow animation), per the PRD accessibility requirement.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the one-time completion flourish animation.
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 28) {
            // THE HEADSTOCK HERO. A pure function of model state; tapping a peg
            // locks onto that string.
            HeadstockView(
                stringNames: model.targets.map(\.note.name),
                layout: headstockLayout,
                activeStringIndex: model.activeStringIndex,
                zone: model.zone,
                isLatched: model.isLatched,
                onTapPeg: { model.lock(toStringIndex: $0) }
            )
            .frame(maxHeight: 320)
            // The whole hero gently scales up on completion as the flourish.
            .scaleEffect(celebrate && !reduceMotion ? 1.03 : 1.0)
            .overlay(alignment: .center) {
                if model.isComplete { completionOverlay }
            }

            // THE DEVIATION METER (hidden once complete — nothing left to tune).
            if !model.isComplete {
                CentsMeterView(cents: model.deviationCents, zone: model.zone)
                    .padding(.horizontal, 24)

                // The gentle next-string nudge.
                if let next = model.suggestedStringIndex, next < model.targets.count {
                    Text("Next: \(model.targets[next].note.name)")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                        .accessibilityLabel("Suggested next string: \(model.targets[next].note.name)")
                }
            }
        }
        // Animate meaningful state changes so things glide rather than snap.
        .animation(.easeOut(duration: 0.15), value: model.deviationCents)
        .animation(.easeOut(duration: 0.3), value: model.isComplete)
        // When completion is reached, fire the one-time flourish. Under Reduce
        // Motion we leave `celebrate` false so only the static "all in tune"
        // state appears — no pulse.
        .onChange(of: model.isComplete) { _, complete in
            guard complete, !reduceMotion else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { celebrate = true }
            // Settle back after the pulse so it reads as a single restrained beat.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.4)) { celebrate = false }
            }
        }
    }

    // MARK: - Completion flourish

    private var completionOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(GKColor.inTune)
                // A soft green halo — restrained, not gaudy.
                .shadow(color: GKColor.inTune.opacity(0.6), radius: celebrate && !reduceMotion ? 18 : 6)
            Text("In tune")
                .font(GKFont.title)
                .foregroundStyle(GKColor.textPrimary)
        }
        .padding(20)
        .background(GKColor.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All strings in tune")
    }

    // MARK: - Layout selection

    /// The peg layout for the current tuning. Standard guitar gets its real 3+3
    /// arrangement; anything else falls back to the generic two-column layout
    /// until #09 supplies per-instrument layouts.
    private var headstockLayout: HeadstockLayout {
        model.targets.count == 6 ? .standardGuitar : .generic(stringCount: model.targets.count)
    }
}

#Preview {
    ZStack {
        GKColor.background.ignoresSafeArea()
        TunerHeroView(model: TuningSessionModel())
    }
}
