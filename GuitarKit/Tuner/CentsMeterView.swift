//
//  CentsMeterView.swift
//  GuitarKit
//
//  One `TunerVisualization`: a linear cents meter. A horizontal track with a
//  center "in tune" detent; an indicator slides left when flat, right when
//  sharp, and centers + turns green when in tune. (The PRD keeps other variants
//  — radial ring, needle, strobe — behind a dev-config A/B panel in slice #07;
//  this is the default linear one.)
//
//  NON-COLOR CHANNELS (PRD story 13): the indicator's horizontal POSITION (left
//  = flat, right = sharp, center = in tune) and the small direction caret convey
//  state without relying on the red/blue/green color at all.
//

import SwiftUI

struct CentsMeterView: View {

    /// Signed cents from the target (+ sharp / − flat), or nil when no reading.
    let cents: Double?
    /// The classified zone, used for the indicator color + center-band fill.
    let zone: TuningZone?

    /// The cents at the far left/right ends of the meter. Beyond this we clamp
    /// the indicator to the edge (you're very out of tune, exact value matters
    /// less than "way flat / way sharp").
    private let range: Double = 50

    var body: some View {
        VStack(spacing: 10) {
            // The signed numeric, in tabular digits so it doesn't jitter.
            Text(centsLabel)
                .font(GKFont.liveNumeric)
                .tabularNumbers()
                .foregroundStyle(indicatorColor)
                .accessibilityLabel(accessibilityLabel)

            GeometryReader { geo in
                let width = geo.size.width
                let mid = width / 2

                ZStack(alignment: .leading) {
                    // The track.
                    Capsule()
                        .fill(GKColor.textSecondary.opacity(0.15))
                        .frame(height: 8)

                    // The center "in tune" detent zone — a subtle green band the
                    // indicator nestles into when you're within ±3¢.
                    Capsule()
                        .fill(GKColor.inTune.opacity(0.25))
                        .frame(width: width * 0.10, height: 8)
                        .position(x: mid, y: 4)

                    // The center tick (the exact target). A positional anchor.
                    Rectangle()
                        .fill(GKColor.textSecondary.opacity(0.6))
                        .frame(width: 2, height: 18)
                        .position(x: mid, y: 4)

                    // The moving indicator.
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 20, height: 20)
                        .position(x: indicatorX(in: width), y: 4)
                        .animation(.easeOut(duration: 0.12), value: cents)
                }
                .frame(height: 20)
            }
            .frame(height: 20)

            // Direction labels at the ends — a non-color cue for which way is
            // which ("turn the peg down" vs "up").
            HStack {
                Label("flat", systemImage: "arrow.down")
                    .labelStyle(.titleAndIcon)
                Spacer()
                Label("sharp", systemImage: "arrow.up")
                    .labelStyle(.titleAndIcon)
            }
            .font(GKFont.caption)
            .foregroundStyle(GKColor.textSecondary)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Geometry

    /// Where the indicator sits horizontally for the current cents value,
    /// clamped to the meter's range.
    private func indicatorX(in width: Double) -> Double {
        guard let cents else { return width / 2 }            // no reading → center
        let clamped = min(max(cents, -range), range)         // keep on the track
        let fraction = (clamped + range) / (2 * range)       // 0 (flat) … 1 (sharp)
        return fraction * width
    }

    // MARK: - Presentation

    private var indicatorColor: Color {
        switch zone {
        case .perfect, .inTune: return GKColor.inTune
        case .flat:             return GKColor.flat
        case .sharp:            return GKColor.sharp
        case nil:               return GKColor.textSecondary
        }
    }

    private var centsLabel: String {
        guard let cents else { return "—" }
        let rounded = Int(cents.rounded())
        let sign = rounded > 0 ? "+" : ""
        return "\(sign)\(rounded)¢"
    }

    private var accessibilityLabel: String {
        guard let cents else { return "No pitch detected" }
        let rounded = Int(cents.rounded())
        switch zone {
        case .perfect:          return "Perfectly in tune"
        case .inTune:           return "In tune"
        case .sharp:            return "\(abs(rounded)) cents sharp"
        case .flat:             return "\(abs(rounded)) cents flat"
        case nil:               return "\(rounded) cents"
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        CentsMeterView(cents: -22, zone: .flat)
        CentsMeterView(cents: 0, zone: .perfect)
        CentsMeterView(cents: 14, zone: .sharp)
        CentsMeterView(cents: nil, zone: nil)
    }
    .padding()
    .background(GKColor.background)
}
