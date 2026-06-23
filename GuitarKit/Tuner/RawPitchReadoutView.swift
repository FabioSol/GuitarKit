//
//  RawPitchReadoutView.swift
//  GuitarKit
//
//  The bare detection readout for slice #03: prove the mic → MPM → screen
//  pipeline works by showing the live note name, its frequency, and how many
//  cents sharp/flat it is. This is intentionally plain — the headstock "hero"
//  visualization arrives in a later slice (#06). What ships here is the
//  tracer-bullet end of the spine: real audio turning into a real note on screen.
//

import SwiftUI

struct RawPitchReadoutView: View {

    /// The latest reading from the detector, or `nil` when nothing is heard.
    /// The parent (TunerView) owns the detector and passes its `reading` in, so
    /// this view stays a dumb, previewable function of its input.
    let reading: PitchReading?

    /// How many cents count as "close enough" to read as in-tune (drives color).
    /// ±5 cents is a common just-noticeable-difference threshold for tuning.
    private let inTuneCents: Double = 5

    var body: some View {
        VStack(spacing: 16) {
            if let reading {
                // BIG NOTE NAME — the hero of this bare screen.
                Text(reading.note.name)
                    .font(GKFont.heroNote)
                    .foregroundStyle(deviationColor(reading.centOffset))
                    // Announce the note (and its tuning state) as one VoiceOver
                    // phrase instead of spelling out "A, 4".
                    .accessibilityLabel(accessibilityPhrase(for: reading))

                // CENTS OFFSET — the signed deviation, in tabular digits so it
                // doesn't jitter as it updates. We hide it from VoiceOver because
                // the phrase above already conveys it.
                Text(centsLabel(reading.centOffset))
                    .font(GKFont.liveNumeric)
                    .tabularNumbers()
                    .foregroundStyle(deviationColor(reading.centOffset))
                    .accessibilityHidden(true)

                // FREQUENCY — the raw measured Hz, the proof the engine is live.
                Text(String(format: "%.1f Hz", reading.frequency))
                    .font(GKFont.caption)
                    .tabularNumbers()
                    .foregroundStyle(GKColor.textSecondary)
                    .accessibilityHidden(true)
            } else {
                // IDLE STATE — no confident pitch. A dash placeholder keeps the
                // layout from jumping when a note appears/disappears.
                Text("—")
                    .font(GKFont.heroNote)
                    .foregroundStyle(GKColor.textSecondary)

                Text("Play a note")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
            }
        }
        // Animate transitions between readings so the note/cents glide rather
        // than snap. `value:` ties the animation to the reading changing.
        .animation(.easeOut(duration: 0.15), value: reading)
    }

    // MARK: - Presentation helpers

    /// Color-code the deviation: green when in tune, red when sharp, blue when
    /// flat — matching the app's tuning palette. (Color is one channel of many;
    /// the sign in `centsLabel` carries the same info without relying on color.)
    private func deviationColor(_ cents: Double) -> Color {
        if abs(cents) <= inTuneCents { return GKColor.inTune }
        return cents > 0 ? GKColor.sharp : GKColor.flat
    }

    /// A signed, rounded cents label like "+7¢", "−3¢", or "0¢".
    private func centsLabel(_ cents: Double) -> String {
        let rounded = Int(cents.rounded())
        // Show an explicit "+" for sharp so the sign always reads at a glance.
        let sign = rounded > 0 ? "+" : ""
        return "\(sign)\(rounded)¢"
    }

    /// A spoken description for VoiceOver, e.g. "A4, 7 cents sharp" / "in tune".
    private func accessibilityPhrase(for reading: PitchReading) -> String {
        let cents = Int(reading.centOffset.rounded())
        let state: String
        if abs(reading.centOffset) <= inTuneCents {
            state = "in tune"
        } else {
            state = "\(abs(cents)) cents \(cents > 0 ? "sharp" : "flat")"
        }
        return "\(reading.note.name), \(state)"
    }
}

#Preview("In tune") {
    RawPitchReadoutView(
        reading: PitchReading(frequency: 110.0, note: Note(pitchClass: .a, octave: 2),
                              centOffset: 1, clarity: 0.98)
    )
}

#Preview("Sharp") {
    RawPitchReadoutView(
        reading: PitchReading(frequency: 82.9, note: Note(pitchClass: .e, octave: 2),
                              centOffset: 12, clarity: 0.95)
    )
}

#Preview("Idle") {
    RawPitchReadoutView(reading: nil)
}
