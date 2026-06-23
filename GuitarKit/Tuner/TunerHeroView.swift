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

            // Below the head: the completion banner once done (so you still SEE
            // all six green pegs), otherwise the deviation meter + next nudge.
            if model.isComplete {
                completionBanner
            } else {
                CentsMeterView(cents: model.deviationCents, zone: model.zone)
                    .padding(.horizontal, 24)

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

    private var completionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(GKColor.inTune)
                // A soft green halo — restrained, not gaudy.
                .shadow(color: GKColor.inTune.opacity(0.6), radius: celebrate && !reduceMotion ? 16 : 5)
            Text("In tune")
                .font(GKFont.title)
                .foregroundStyle(GKColor.textPrimary)
        }
        .padding(.vertical, 8)
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

// MARK: - Previews
//
// These give a live, tweakable canvas for the hero WITHOUT needing the mic:
// each one builds a `TuningSessionModel` and feeds it scripted readings so you
// can see (and hot-edit) every state. Open this file in Xcode and the canvas on
// the right shows them — edit a color/size/spacing and it updates instantly.
//
// (To see it react to *real* playing: run the app on the iOS Simulator — it uses
// your Mac's microphone — or on a device, and play/whistle a note.)

#if DEBUG
/// Build a model driven by a scripted list of (frequency, time) steps. A `nil`
/// frequency is silence. Uses an injected clock so hold-to-latch is deterministic.
@MainActor
private func previewModel(_ steps: [(Double?, Double)]) -> TuningSessionModel {
    final class Clock { var t: Double = 0 }
    let clock = Clock()
    let model = TuningSessionModel(now: { clock.t })
    for (freq, t) in steps {
        clock.t = t
        let reading = freq.map {
            PitchReading(frequency: $0, note: Note.from(midiNumber: 69), centOffset: 0, clarity: 1)
        }
        model.ingest(reading)
    }
    return model
}

/// Exact equal-tempered frequency of a note, optionally detuned by `cents`.
@MainActor
private func previewHz(_ pc: PitchClass, _ oct: Int, cents: Double = 0) -> Double {
    PitchCalculator().frequency(of: Note(pitchClass: pc, octave: oct)) * pow(2.0, cents / 1200.0)
}

private func heroCanvas(_ model: TuningSessionModel) -> some View {
    ZStack {
        GKColor.background.ignoresSafeArea()
        TunerHeroView(model: model)
    }
    .preferredColorScheme(.dark)   // the app is dark-first
}

#Preview("Idle") {
    heroCanvas(previewModel([]))
}

#Preview("18¢ flat (low E)") {
    heroCanvas(previewModel([(previewHz(.e, 2, cents: -18), 0)]))
}

#Preview("In tune (A, +2¢)") {
    heroCanvas(previewModel([(previewHz(.a, 2, cents: 2), 0)]))
}

#Preview("Complete (all green)") {
    let notes: [(PitchClass, Int)] = [(.e, 2), (.a, 2), (.d, 3), (.g, 3), (.b, 3), (.e, 4)]
    var steps: [(Double?, Double)] = []
    for (i, n) in notes.enumerated() {
        let base = Double(i) * 2.0
        steps.append((previewHz(n.0, n.1), base))        // enter tolerance
        steps.append((previewHz(n.0, n.1), base + 1.0))  // hold → latch
        steps.append((nil, base + 1.5))                  // silence between strings
    }
    return heroCanvas(previewModel(steps))
}
#endif
