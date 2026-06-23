//
//  HeadstockView.swift
//  GuitarKit
//
//  The hero: a stylized (not skeuomorphic) headstock with one peg per string in
//  its physical position. The active string's peg highlights; latched strings go
//  green with a check. Tapping a peg locks onto that string (manual override).
//
//  SOLID CONTENT, NEVER GLASS (PRD): the hero carries the semantic tuning colors
//  (red/blue/green), so it must sit on opaque fills — glass blur would wash out
//  the very contrast the colors depend on. That's why everything here uses solid
//  `GKColor` fills rather than `.gkGlass(...)`.
//

import SwiftUI

struct HeadstockView: View {

    // MARK: Inputs (a pure function of state — the model passes these in)

    /// Note name to print on each peg, in string order (low → high).
    let stringNames: [String]
    /// Peg positions for this instrument's headstock.
    let layout: HeadstockLayout
    /// The string currently being tuned (peg to highlight), or nil.
    let activeStringIndex: Int?
    /// The current tuning zone of the active string (drives the highlight color).
    let zone: TuningZone?
    /// Whether a given string has latched in tune.
    let isLatched: (Int) -> Bool
    /// Called when a peg is tapped — lock onto that string.
    let onTapPeg: (Int) -> Void

    /// Respect the user's Reduce Motion setting: when on, we skip the pulsing
    /// highlight animation and just show the static highlighted state.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // `GeometryReader` hands us the actual pixel size so we can convert each
        // peg's normalized (0...1) position into a real point.
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                // The headstock silhouette — a solid, tapered rounded shape.
                HeadstockShape()
                    .fill(GKColor.background)
                    .overlay(
                        HeadstockShape().stroke(
                            GKColor.textSecondary.opacity(0.25),
                            lineWidth: 1.5
                        )
                    )

                // The nut: a small bar at the bottom where the strings leave the
                // headstock. Purely decorative scene-setting.
                Capsule()
                    .fill(GKColor.textSecondary.opacity(0.35))
                    .frame(width: size.width * 0.5, height: 6)
                    .position(x: size.width * 0.5, y: size.height * 0.97)

                // One peg per string, placed at its normalized position.
                ForEach(layout.pegs.indices, id: \.self) { index in
                    let peg = layout.pegs[index]
                    PegView(
                        name: index < stringNames.count ? stringNames[index] : "",
                        isActive: activeStringIndex == index,
                        isLatched: isLatched(index),
                        zone: activeStringIndex == index ? zone : nil,
                        reduceMotion: reduceMotion
                    )
                    .position(x: peg.x * size.width, y: peg.y * size.height)
                    // Tap anywhere on the peg to lock onto that string.
                    .onTapGesture { onTapPeg(index) }
                }
            }
        }
        // A portrait-ish aspect ratio so the headstock reads as a headstock.
        .aspectRatio(0.62, contentMode: .fit)
    }
}

// MARK: - A single peg

/// One tuning peg: a solid rounded "key" with the note name, that highlights
/// when active and turns green when latched.
private struct PegView: View {
    let name: String
    let isActive: Bool
    let isLatched: Bool
    let zone: TuningZone?
    let reduceMotion: Bool

    /// Drives a gentle pulse on the active peg (disabled under Reduce Motion).
    @State private var pulse = false

    var body: some View {
        ZStack {
            // The peg body. Latched → green; active → tinted by zone; else quiet.
            Circle()
                .fill(fillColor)
                .overlay(Circle().strokeBorder(ringColor, lineWidth: isActive ? 3 : 1.5))
                // The active peg subtly pulses to draw the eye — this is a MOTION
                // cue for the active string that doesn't depend on color (helps
                // colorblind users locate "the one I'm tuning"). Off under Reduce
                // Motion, where the thicker ring + scale carry the meaning instead.
                .scaleEffect((isActive && pulse && !reduceMotion) ? 1.06 : 1.0)

            // The label: the note name, or a check once latched.
            if isLatched {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(name)
                    .font(GKFont.navLabel)
                    .tabularNumbers()
                    .foregroundStyle(isActive ? GKColor.textPrimary : GKColor.textSecondary)
            }
        }
        // Active pegs sit slightly larger so the highlight reads without color.
        .frame(width: isActive ? 52 : 44, height: isActive ? 52 : 44)
        .animation(.easeOut(duration: 0.2), value: isActive)
        .animation(.easeOut(duration: 0.2), value: isLatched)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: isActive) { _, _ in startPulseIfNeeded() }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// Begin (or stop) the repeating pulse depending on active state.
    private func startPulseIfNeeded() {
        guard isActive, !reduceMotion else { pulse = false; return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    private var fillColor: Color {
        if isLatched { return GKColor.inTune }
        if isActive {
            switch zone {
            case .perfect, .inTune: return GKColor.inTune.opacity(0.85)
            case .flat:             return GKColor.flat.opacity(0.85)
            case .sharp:            return GKColor.sharp.opacity(0.85)
            case nil:               return GKColor.accent.opacity(0.30)
            }
        }
        return GKColor.textSecondary.opacity(0.15)
    }

    private var ringColor: Color {
        if isLatched { return GKColor.inTune }
        if isActive { return GKColor.accent }
        return GKColor.textSecondary.opacity(0.3)
    }

    private var accessibilityLabel: String {
        if isLatched { return "\(name) string, in tune" }
        if isActive { return "\(name) string, tuning now" }
        return "\(name) string, tap to select"
    }
}

// MARK: - The headstock outline shape

/// A simple, stylized headstock silhouette: a vertically-tapered rounded shape,
/// wider at the top (where the pegs fan out) and narrowing toward the nut. Drawn
/// procedurally so it scales cleanly and reads as "headstock" without imitating
/// any real wood grain or brand.
struct HeadstockShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let corner = w * 0.18

        // Slightly narrower at the bottom (toward the nut) than the top.
        let topInset = w * 0.06
        let bottomInset = w * 0.18

        // Four corner points of a tapered rectangle.
        let topLeft = CGPoint(x: rect.minX + topInset, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - topInset, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX - bottomInset, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX + bottomInset, y: rect.maxY)
        _ = h

        // Trace the outline with rounded corners via arcs/quad curves. Using
        // `addRoundedRect`-style manual rounding keeps the taper.
        path.move(to: CGPoint(x: topLeft.x + corner, y: topLeft.y))
        path.addLine(to: CGPoint(x: topRight.x - corner, y: topRight.y))
        path.addQuadCurve(to: CGPoint(x: topRight.x, y: topRight.y + corner),
                          control: topRight)
        path.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - corner))
        path.addQuadCurve(to: CGPoint(x: bottomRight.x - corner, y: bottomRight.y),
                          control: bottomRight)
        path.addLine(to: CGPoint(x: bottomLeft.x + corner, y: bottomLeft.y))
        path.addQuadCurve(to: CGPoint(x: bottomLeft.x, y: bottomLeft.y - corner),
                          control: bottomLeft)
        path.addLine(to: CGPoint(x: topLeft.x, y: topLeft.y + corner))
        path.addQuadCurve(to: CGPoint(x: topLeft.x + corner, y: topLeft.y),
                          control: topLeft)
        path.closeSubpath()
        return path
    }
}
