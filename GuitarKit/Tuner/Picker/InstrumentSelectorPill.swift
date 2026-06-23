//
//  InstrumentSelectorPill.swift
//  GuitarKit
//
//  The compact "selector pill" that sits on the Tuner face and shows the current
//  instrument + tuning (e.g. "Guitar · Drop D"). Tapping it opens the instrument
//  picker sheet (`InstrumentPickerView`).
//
//  WHY "QUIET" STYLING?
//  The pill is CHROME, not the hero. The Tuner's star is the big headstock and the
//  in-tune feedback; the pill just tells you what you're tuning and lets you
//  change it. So it's deliberately minimal — a small capsule, secondary text, a
//  subtle chevron — so it never competes with the semantic tuning colours or the
//  hero note. (PRD's visual identity: the selector pill lives on the "chrome /
//  functional layer".) We keep it as a plain capsule here; the glass treatment the
//  PRD mentions for chrome can be layered on by the presenter without changing
//  this view's API.
//
//  WHAT THIS VIEW DOES NOT DO:
//  It holds no state and knows nothing about persistence or the picker — it's a
//  pure button. The presenter passes the two display strings and an `action` that
//  opens the sheet. That keeps the pill reusable and trivial to preview/test.
//

import SwiftUI

struct InstrumentSelectorPill: View {

    // MARK: Inputs

    /// The current instrument's display name, e.g. "Guitar". Passed in (not derived
    /// from a model) so the pill stays a dumb, reusable label.
    let instrumentName: String

    /// The current tuning's display name, e.g. "Drop D".
    let tuningName: String

    /// What tapping the pill does — the presenter wires this to "present the picker
    /// sheet". Kept as a closure so the pill doesn't own any presentation state.
    let action: () -> Void

    // MARK: Body

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Instrument name in primary text, tuning in secondary, separated
                // by a thin middle dot — a compact "Guitar · Drop D".
                Text(instrumentName)
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textPrimary)

                Text("·")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)

                Text(tuningName)
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)

                // A small chevron hints "tap to change / opens a sheet". Down-chevron
                // is the conventional "reveals a picker" glyph.
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(GKColor.textSecondary)
                    // Decorative — the button's accessibility label already conveys
                    // that this opens the picker.
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            // A capsule background in a faint fill so the pill reads as a tappable
            // chip without shouting. `.quaternary` is a system fill that stays
            // subtle in both light and dark.
            .background(.quaternary, in: Capsule())
        }
        // `.plain` so we control the look entirely (no default blue button tint),
        // keeping the pill quiet.
        .buttonStyle(.plain)
        // One combined VoiceOver element that reads the whole pill and explains the
        // tap. We spell out the current selection plus "opens picker" so a
        // non-sighted user knows both the state and the affordance.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Instrument: \(instrumentName), \(tuningName)")
        .accessibilityHint("Opens the instrument and tuning picker")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#Preview {
    // Show it on a representative dark backdrop so the quiet styling is visible.
    VStack(spacing: 20) {
        InstrumentSelectorPill(
            instrumentName: "Guitar",
            tuningName: "Drop D",
            action: { print("Open picker") }
        )
        InstrumentSelectorPill(
            instrumentName: "5-String Bass",
            tuningName: "Standard",
            action: {}
        )
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GKColor.background)
}
