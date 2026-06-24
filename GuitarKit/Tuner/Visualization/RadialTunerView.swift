//
//  RadialTunerView.swift
//  GuitarKit
//
//  One `TunerVisualization`: a RADIAL gauge (think speedometer). A semicircular
//  arc track sits above a big centred cents number; an indicator dot rides the
//  arc — far left when very flat, straight up at the top when in tune, far right
//  when very sharp. This is the A/B alternative to the default linear meter
//  (`CentsMeterView`); slice #07's dev panel flips between them live.
//
//  NON-COLOR CHANNELS (PRD story 13): like the linear meter, state is conveyed
//  WITHOUT relying on color — here by the indicator's ANGLE (left = flat, top =
//  in tune, right = sharp) and a small filled wedge growing toward it. The
//  red/blue/green is an extra layer, never the only signal.
//

import SwiftUI

struct RadialTunerView: View {

    /// Signed cents from the target (+ sharp / − flat), or nil when no reading.
    let cents: Double?
    /// The classified zone, used for the indicator color + centre number.
    let zone: TuningZone?

    /// The memberwise initializer, written explicitly so it satisfies the
    /// `TunerVisualization` protocol's `init(cents:zone:)` requirement (and so it
    /// is callable from `TunerVisualizationKind.view`).
    init(cents: Double?, zone: TuningZone?) {
        self.cents = cents
        self.zone = zone
    }

    /// Cents at the far ends of the arc. Beyond this we clamp to the edge — when
    /// you're wildly out, "way flat / way sharp" matters more than the exact value.
    private let range: Double = 50

    /// How wide the gauge opens, in degrees each side of straight-up. 75° each way
    /// gives a generous 150° sweep that still reads as "a dial", not a full circle.
    private let halfSweepDegrees: Double = 75

    var body: some View {
        VStack(spacing: 12) {
            // The dial itself, drawn into a fixed-aspect canvas so the trig math
            // has stable dimensions to work against.
            GeometryReader { geo in
                let size = geo.size
                // The arc's centre is the BOTTOM-centre of the canvas, so the
                // semicircle bows upward like a speedometer.
                let center = CGPoint(x: size.width / 2, y: size.height)
                let radius = min(size.width / 2, size.height) - 16

                ZStack {
                    // 1) THE TRACK — a faint arc from the left end to the right end.
                    ArcShape(startDegrees: -halfSweepDegrees - 90,
                             endDegrees: halfSweepDegrees - 90,
                             radius: radius,
                             center: center)
                        .stroke(GKColor.textSecondary.opacity(0.15),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))

                    // 2) THE "IN TUNE" DETENT — a short bright arc at the very top
                    // (the target) the indicator nestles into when centred.
                    ArcShape(startDegrees: -8 - 90,
                             endDegrees: 8 - 90,
                             radius: radius,
                             center: center)
                        .stroke(GKColor.inTune.opacity(0.30),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))

                    // 3) THE FILLED WEDGE — from the top (target) out to the
                    // current angle, so the *amount* you're off reads as a length,
                    // not just a dot position. A second non-color cue.
                    ArcShape(startDegrees: -90,
                             endDegrees: indicatorDegrees - 90,
                             radius: radius,
                             center: center)
                        .stroke(indicatorColor.opacity(0.55),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .animation(.easeOut(duration: 0.12), value: cents)

                    // 4) THE INDICATOR DOT — rides the arc at the current angle.
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: 22, height: 22)
                        .position(pointOnArc(degrees: indicatorDegrees - 90,
                                             radius: radius,
                                             center: center))
                        .animation(.easeOut(duration: 0.12), value: cents)

                    // 5) THE CENTRE TICK at the top (the exact target) — a fixed
                    // positional anchor so "straight up = in tune" is unmistakable.
                    Circle()
                        .fill(GKColor.textSecondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .position(pointOnArc(degrees: -90, radius: radius, center: center))
                }
            }
            .frame(height: 120)

            // The signed numeric, tabular so it doesn't jitter as it updates.
            Text(centsLabel)
                .font(GKFont.liveNumeric)
                .tabularNumbers()
                .foregroundStyle(indicatorColor)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    // MARK: - Geometry

    /// The indicator's angle in "gauge degrees": 0 = straight up (in tune),
    /// negative = left (flat), positive = right (sharp), clamped to the sweep.
    private var indicatorDegrees: Double {
        guard let cents else { return 0 }                 // no reading → top centre
        let clamped = min(max(cents, -range), range)      // keep on the arc
        let fraction = clamped / range                    // −1 (flat) … +1 (sharp)
        return fraction * halfSweepDegrees
    }

    /// Convert a polar angle (degrees, 0° = right, measured clockwise in screen
    /// space where +y points DOWN) into a point on the arc of `radius` around
    /// `center`. We pass angles already offset by −90 so "up" is the middle.
    private func pointOnArc(degrees: Double, radius: Double, center: CGPoint) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians),
                       y: center.y + radius * sin(radians))
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

// MARK: - Conformance

// `CentsMeterView` already has the matching `init(cents:zone:)`; declaring the
// conformance here makes the "all visualizations share one interface" contract
// real and compiler-checked. (See `TunerVisualization`.)
extension RadialTunerView: TunerVisualization {}

// MARK: - A tiny arc shape

/// A stroke-able arc between two angles. SwiftUI's `Path.addArc` does the work;
/// wrapping it in a `Shape` lets us `.stroke(...)` it like any other shape and
/// animate cleanly. Angles are in DEGREES in screen space (0° = right, growing
/// clockwise because screen +y points down).
private struct ArcShape: Shape {
    let startDegrees: Double
    let endDegrees: Double
    let radius: Double
    let center: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            // When the end angle is less than the start (indicator on the flat
            // side) we sweep the other way so the wedge still draws toward it.
            clockwise: endDegrees < startDegrees
        )
        return path
    }
}

#Preview {
    VStack(spacing: 40) {
        RadialTunerView(cents: -28, zone: .flat)
        RadialTunerView(cents: 0, zone: .perfect)
        RadialTunerView(cents: 16, zone: .sharp)
        RadialTunerView(cents: nil, zone: nil)
    }
    .padding()
    .background(GKColor.background)
}
