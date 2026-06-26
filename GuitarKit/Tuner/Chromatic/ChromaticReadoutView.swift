//
//  ChromaticReadoutView.swift
//  GuitarKit
//
//  The CHROMATIC-mode hero (the "back" face of the hero flip). Unlike the
//  targeted tuner — which compares you to a chosen string — chromatic mode simply
//  names the NEAREST note to whatever you play and shows how many cents off it is.
//  It reuses the very same detection (`PitchReading` already names the nearest
//  note) and the shared `CentsMeterView`, with a tuning-fork motif to make the
//  mode feel distinct and thematic (PRD stories 15/16).
//
//  Solid content (no glass), like the rest of the hero, so the semantic
//  sharp/flat/in-tune colors keep their contrast.
//

import SwiftUI

struct ChromaticReadoutView: View {

    /// The latest detector reading (nearest note + cents), or `nil` for silence.
    /// The parent passes `detector.reading` straight in — chromatic mode needs no
    /// string targets, just the raw reading.
    let reading: PitchReading?

    var body: some View {
        // Classify the deviation with the pure chromatic classifier (matches the
        // tuner's ±1/±3 thresholds, so both modes agree on "in tune").
        let zone = ChromaticZone.classify(cents: reading?.centOffset)

        VStack(spacing: 16) {
            // The note over a faint tuning-fork motif — the thematic backdrop.
            ZStack {
                Image(systemName: "tuningfork")
                    .font(.system(size: 132))
                    .foregroundStyle(GKColor.textSecondary.opacity(0.08))
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    if let reading {
                        // Big nearest-note name, colored by how in-tune it is.
                        Text(reading.note.name)
                            .heroNoteFont()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)   // shrink-to-fit at large Dynamic Type sizes
                            .foregroundStyle(color(for: zone))
                            .accessibilityLabel(accessibilityPhrase(reading, zone))

                        // The raw frequency — proof the engine is live (hidden from
                        // VoiceOver; the phrase above already conveys the state).
                        Text(String(format: "%.1f Hz", reading.frequency))
                            .font(GKFont.caption)
                            .tabularNumbers()
                            .foregroundStyle(GKColor.textSecondary)
                            .accessibilityHidden(true)
                    } else {
                        Text("—")
                            .heroNoteFont()
                            .foregroundStyle(GKColor.textSecondary)
                        Text("Play any note")
                            .font(GKFont.caption)
                            .foregroundStyle(GKColor.textSecondary)
                    }
                }
            }

            // The shared deviation meter — same one the targeted tuner uses.
            CentsMeterView(cents: reading?.centOffset, zone: zone)
                .padding(.horizontal, 24)
        }
        .animation(.easeOut(duration: 0.15), value: reading)
    }

    // MARK: - Presentation

    /// Map a zone to the tuning palette (green in tune, red sharp, blue flat).
    private func color(for zone: TuningZone?) -> Color {
        switch zone {
        case .perfect, .inTune: return GKColor.inTune
        case .flat:             return GKColor.flat
        case .sharp:            return GKColor.sharp
        case nil:               return GKColor.textSecondary
        }
    }

    private func accessibilityPhrase(_ reading: PitchReading, _ zone: TuningZone?) -> String {
        let cents = Int(reading.centOffset.rounded())
        switch zone {
        case .perfect:          return "\(reading.note.name), perfectly in tune"
        case .inTune:           return "\(reading.note.name), in tune"
        case .sharp:            return "\(reading.note.name), \(abs(cents)) cents sharp"
        case .flat:             return "\(reading.note.name), \(abs(cents)) cents flat"
        case nil:               return reading.note.name
        }
    }
}

#Preview("In tune") {
    ZStack {
        GKColor.background.ignoresSafeArea()
        ChromaticReadoutView(reading: PitchReading(
            frequency: 440, note: Note(pitchClass: .a, octave: 4), centOffset: 1, clarity: 1))
    }
    .preferredColorScheme(.dark)
}

#Preview("Sharp") {
    ZStack {
        GKColor.background.ignoresSafeArea()
        ChromaticReadoutView(reading: PitchReading(
            frequency: 312, note: Note(pitchClass: .dSharp, octave: 4), centOffset: 18, clarity: 1))
    }
    .preferredColorScheme(.dark)
}

#Preview("Idle") {
    ZStack {
        GKColor.background.ignoresSafeArea()
        ChromaticReadoutView(reading: nil)
    }
    .preferredColorScheme(.dark)
}
