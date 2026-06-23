//
//  TuningSessionView.swift
//  GuitarKit
//
//  The minimal/placeholder UI for the targeted tuning session (slice #05). The
//  goal here is to make the *state machine* visible and demoable — not to be the
//  final look. The headstock "hero" (slice #06) replaces the body of this screen
//  with stylized pegs; the logic and the string-indicator interactions proven
//  here carry straight over.
//
//  WHAT IT SHOWS:
//    • the active string's target note + signed cents + flat/sharp/in-tune zone,
//    • a row of string "chips" — green when latched, outlined when active,
//      tappable to lock onto (override),
//    • a gentle "next: …" nudge,
//    • an "all in tune" banner at completion.
//

import SwiftUI

struct TuningSessionView: View {

    /// The session model. `@Bindable` isn't needed (we don't two-way bind), but
    /// the view re-renders because the model is `@Observable` and we read its
    /// properties here.
    let model: TuningSessionModel

    /// Cents within which we still want to show the number steady; purely visual.
    var body: some View {
        VStack(spacing: 28) {
            // COMPLETION banner, or the live deviation readout.
            if model.isComplete {
                completionBanner
            } else {
                activeReadout
            }

            // The string indicators (tap to lock).
            stringChips

            // Next-string nudge (hidden once complete).
            if !model.isComplete, let next = model.suggestedStringIndex {
                Text("Next: \(noteName(next))")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
                    .accessibilityLabel("Suggested next string: \(noteName(next))")
            }
        }
        .padding()
        .animation(.easeOut(duration: 0.15), value: model.deviationCents)
        .animation(.easeOut(duration: 0.25), value: model.isComplete)
    }

    // MARK: - Active deviation readout

    @ViewBuilder
    private var activeReadout: some View {
        if let index = model.activeStringIndex {
            VStack(spacing: 12) {
                // Big target note name, colored by how close we are.
                Text(noteName(index))
                    .font(GKFont.heroNote)
                    .foregroundStyle(zoneColor(model.zone))
                    .accessibilityLabel(readoutAccessibilityLabel(index))

                // Signed cents (tabular so it doesn't jitter). Hidden from
                // VoiceOver since the label above already speaks it.
                if let cents = model.deviationCents {
                    Text(centsLabel(cents))
                        .font(GKFont.liveNumeric)
                        .tabularNumbers()
                        .foregroundStyle(zoneColor(model.zone))
                        .accessibilityHidden(true)
                } else {
                    Text("listening…")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }
            }
        } else {
            // Nothing played yet.
            VStack(spacing: 12) {
                Text("—")
                    .font(GKFont.heroNote)
                    .foregroundStyle(GKColor.textSecondary)
                Text("Play a string")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
            }
        }
    }

    // MARK: - String chips

    private var stringChips: some View {
        HStack(spacing: 10) {
            // `targets.indices` gives us each string's position to render + lock.
            ForEach(model.targets.indices, id: \.self) { index in
                let latched = model.isLatched(index)
                let active = model.activeStringIndex == index

                Button {
                    model.lock(toStringIndex: index)
                } label: {
                    Text(noteName(index))
                        .font(GKFont.navLabel)
                        .tabularNumbers()
                        .frame(minWidth: 40)
                        .padding(.vertical, 10)
                        .background(chipBackground(latched: latched, active: active))
                        .foregroundStyle(latched ? Color.white : GKColor.textPrimary)
                        .clipShape(Capsule())
                        // A non-color cue for "active": an outline ring.
                        .overlay(
                            Capsule().strokeBorder(
                                active ? GKColor.accent : .clear,
                                lineWidth: 2
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chipAccessibilityLabel(index, latched: latched, active: active))
            }
        }
    }

    // MARK: - Completion

    private var completionBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(GKColor.inTune)
            Text("In tune")
                .font(GKFont.largeTitle)
                .foregroundStyle(GKColor.textPrimary)
        }
        // A modest combined accessibility announcement.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All strings in tune")
    }

    // MARK: - Presentation helpers

    /// The display name of string `index`'s target note (already capo-shifted by
    /// the calculator that built the target).
    private func noteName(_ index: Int) -> String {
        model.targets[index].note.name
    }

    /// Map a zone to the tuning palette. Color is one channel among the zone
    /// text, the cents sign, and the active outline — never the only signal.
    private func zoneColor(_ zone: TuningZone?) -> Color {
        switch zone {
        case .perfect, .inTune: return GKColor.inTune
        case .flat:             return GKColor.flat
        case .sharp:            return GKColor.sharp
        case nil:               return GKColor.textSecondary
        }
    }

    /// Background for a chip: green when latched, faint accent when active,
    /// otherwise a quiet fill.
    private func chipBackground(latched: Bool, active: Bool) -> Color {
        if latched { return GKColor.inTune }
        if active { return GKColor.accent.opacity(0.15) }
        return GKColor.textSecondary.opacity(0.12)
    }

    /// A signed cents label like "+7¢" / "−3¢".
    private func centsLabel(_ cents: Double) -> String {
        let rounded = Int(cents.rounded())
        let sign = rounded > 0 ? "+" : ""
        return "\(sign)\(rounded)¢"
    }

    private func readoutAccessibilityLabel(_ index: Int) -> String {
        let name = noteName(index)
        switch model.zone {
        case .perfect:          return "\(name), perfectly in tune"
        case .inTune:           return "\(name), in tune"
        case .flat, .sharp:
            let cents = Int((model.deviationCents ?? 0).rounded())
            let dir = model.zone == .sharp ? "sharp" : "flat"
            return "\(name), \(abs(cents)) cents \(dir)"
        case nil:               return name
        }
    }

    private func chipAccessibilityLabel(_ index: Int, latched: Bool, active: Bool) -> String {
        let name = noteName(index)
        if latched { return "\(name) string, in tune" }
        if active { return "\(name) string, currently tuning" }
        return "\(name) string, tap to lock"
    }
}

#Preview("Tuning") {
    ZStack {
        GKColor.background.ignoresSafeArea()
        TuningSessionView(model: TuningSessionModel())
    }
}
