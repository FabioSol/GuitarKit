//
//  HeadstockView.swift
//  GuitarKit
//
//  The hero: a stylized (not skeuomorphic) 3+3 guitar headstock with one peg per
//  string in its physical position. The active string's peg highlights; latched
//  strings go green with a check. Tapping a peg locks onto that string.
//
//  SOLID CONTENT, NEVER GLASS (PRD): the hero carries the semantic tuning colors
//  (red/blue/green), so it sits on opaque fills — glass blur would wash out the
//  very contrast the colors depend on.
//
//  ASSET-READY SEAM: the silhouette is one isolated subview (`headstockBody`).
//  Today it's drawn procedurally with `HeadstockShape`; the Instruments slice
//  (#09) can swap that single subview for a per-instrument vector `Image` asset
//  without touching the peg-overlay logic, which stays live for color + taps.
//

import SwiftUI

struct HeadstockView: View {

    // MARK: Inputs (a pure function of state — the model passes these in)

    /// Note name to print on each peg, in string order (low → high).
    let stringNames: [String]
    /// The head description: art source, aspect ratio, and peg anchors. Authored
    /// externally (designer SVG + JSON) and decoded into `HeadstockSpec`.
    let spec: HeadstockSpec
    /// The string currently being tuned (peg to highlight), or nil.
    let activeStringIndex: Int?
    /// The current tuning zone of the active string (drives the highlight color).
    let zone: TuningZone?
    /// Whether a given string has latched in tune.
    let isLatched: (Int) -> Bool
    /// Called when a peg is tapped — lock onto that string.
    let onTapPeg: (Int) -> Void

    /// Respect Reduce Motion: when on we skip the pulsing highlight and show the
    /// static highlighted state instead.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // `GeometryReader` gives us the real size so each normalized peg position
        // (and the silhouette and string lines) map into the SAME coordinate
        // space — which is what makes the pegs sit exactly on the head.
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                // 1) The headstock silhouette (the swappable "art" layer).
                headstockBody

                // 2) The strings: thin lines fanning from the nut up to each peg.
                stringLines(in: size)

                // 3) The nut ("bone"): a short bar where the strings leave the head.
                // Position + width come from the spec so it sits on the real neck
                // (offset for the asymmetric bass, narrow for the violin pegbox).
                let nut = spec.resolvedNut
                Capsule()
                    .fill(GKColor.textSecondary.opacity(0.55))
                    .frame(width: size.width * nut.width, height: 5)
                    .position(x: size.width * nut.x, y: size.height * nut.y)

                // 4) One peg per string, placed at its normalized position.
                ForEach(spec.pegs.indices, id: \.self) { index in
                    let peg = spec.pegs[index]
                    PegView(
                        name: index < stringNames.count ? stringNames[index] : "",
                        isActive: activeStringIndex == index,
                        isLatched: isLatched(index),
                        zone: activeStringIndex == index ? zone : nil,
                        reduceMotion: reduceMotion
                    )
                    .position(x: peg.x * size.width, y: peg.y * size.height)
                    .onTapGesture { onTapPeg(index) }
                }
            }
        }
        // Aspect ratio comes from the spec so each instrument reserves the right
        // shape (taller than wide for a guitar).
        .aspectRatio(spec.aspectRatio, contentMode: .fit)
    }

    // MARK: - The silhouette (asset-swappable layer)

    /// The head art. If the spec names an asset (a designer's imported SVG) we use
    /// its SILHOUETTE; otherwise we draw the built-in procedural shape. Pegs
    /// overlay on top either way.
    @ViewBuilder
    private var headstockBody: some View {
        if let art = spec.artAsset {
            // Paint the per-instrument silhouette with an ADAPTIVE gradient (masked
            // by the SVG's shape) rather than rendering the SVG's own fill. The art
            // bakes in dark gray stop-colors ("on the app's dark-first background"),
            // so in LIGHT mode it stayed dark — making the dark peg note labels
            // drawn on top hard to read. Masking an adaptive gradient keeps each
            // instrument's unique outline while tracking the color scheme exactly
            // like the procedural fallback does.
            panelGradient
                .mask(
                    Image(art)
                        .resizable()
                        .scaledToFit()
                )
        } else {
            HeadstockShape()
                .fill(panelGradient)
                .background(HeadstockShape().fill(GKColor.background))
                .overlay(
                    HeadstockShape().stroke(GKColor.textSecondary.opacity(0.45), lineWidth: 1.5)
                )
        }
    }

    /// The faintly-raised "panel" sheen for the head, as two adaptive shades of the
    /// primary label color (light over light, light-on-dark over dark). The 0.20→
    /// 0.10 range approximates the original SVG's hand-picked dark gradient in dark
    /// mode while inverting cleanly to a soft gray panel in light mode. Shared by
    /// both the SVG-silhouette and procedural paths so they read identically.
    private var panelGradient: LinearGradient {
        LinearGradient(
            colors: [
                GKColor.textPrimary.opacity(0.20),
                GKColor.textPrimary.opacity(0.10)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Strings

    /// Thin lines fanning from the nut up to where each string winds — the cue that
    /// ties the pegs to "where the string goes". Drawn beneath the pegs.
    ///
    /// Two things are now data-driven (so each instrument behaves correctly):
    ///   • only strings with `crossesNut != false` fan from the nut, and their nut
    ///     anchors are spread evenly across the (spec'd) nut bar IN PITCH ORDER — so
    ///     dropping the banjo's drone out of the fan re-centres the other four; and
    ///   • each line ends at the string's winding point (`stringX/Y`, default the
    ///     dot), letting the violin's strings run up the pegbox centre instead of
    ///     out to the side buttons the dots sit on.
    private func stringLines(in size: CGSize) -> some View {
        let nut = spec.resolvedNut
        let nutY = nut.y * size.height
        let nutLeft = (nut.x - nut.width / 2) * size.width
        let nutSpan = nut.width * size.width

        // Keep the outer strings off the very ENDS of the nut bar — on a real nut
        // the first and last strings sit a little inside the edges, not flush. We
        // spread the fan across the central `(1 - 2·inset)` of the bar.
        let edgeInset: CGFloat = 0.12
        let fanLeft = nutLeft + nutSpan * edgeInset
        let fanSpan = nutSpan * (1 - 2 * edgeInset)

        // The strings that actually cross the nut, in pitch (index) order.
        let fanned = spec.pegs.indices.filter { spec.pegs[$0].crossesNut ?? true }

        return Path { path in
            guard fanned.count > 0 else { return }
            for (order, i) in fanned.enumerated() {
                // Spread the crossing strings evenly across the inset nut span.
                let frac = fanned.count > 1 ? CGFloat(order) / CGFloat(fanned.count - 1) : 0.5
                let nutX = fanLeft + fanSpan * frac
                let peg = spec.pegs[i]
                let endX = (peg.stringX ?? peg.x) * size.width
                let endY = (peg.stringY ?? peg.y) * size.height
                path.move(to: CGPoint(x: nutX, y: nutY))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
        }
        .stroke(GKColor.textSecondary.opacity(0.30), lineWidth: 1)
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
            Circle()
                .fill(fillColor)
                .overlay(Circle().strokeBorder(ringColor, lineWidth: isActive ? 3 : 1.5))
                // Active peg subtly pulses — a MOTION cue for "the one I'm tuning"
                // that doesn't depend on color (helps colorblind users). Off under
                // Reduce Motion, where the thicker ring + scale carry the meaning.
                .scaleEffect((isActive && pulse && !reduceMotion) ? 1.06 : 1.0)

            if isLatched {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(name)
                    .font(GKFont.navLabel)
                    .tabularNumbers()
                    .foregroundStyle(isActive ? GKColor.textPrimary : GKColor.textSecondary)
            }
        }
        // Active pegs sit slightly larger so the highlight reads without color.
        .frame(width: isActive ? 48 : 42, height: isActive ? 48 : 42)
        .animation(.easeOut(duration: 0.2), value: isActive)
        .animation(.easeOut(duration: 0.2), value: isLatched)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: isActive) { _, _ in startPulseIfNeeded() }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

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
        return GKColor.textSecondary.opacity(0.18)
    }

    private var ringColor: Color {
        if isLatched { return GKColor.inTune }
        if isActive { return GKColor.accent }
        return GKColor.textSecondary.opacity(0.35)
    }

    private var accessibilityLabel: String {
        if isLatched { return "\(name) string, in tune" }
        if isActive { return "\(name) string, tuning now" }
        return "\(name) string, tap to select"
    }
}

// MARK: - The headstock outline shape

/// A stylized 3+3 acoustic / Les-Paul "open-book" headstock: symmetric, widest
/// near the top where the tuners sit, with a soft twin-hump top and a gentle
/// center notch, tapering to a narrower nut at the bottom. Drawn procedurally so
/// it scales cleanly and reads as "headstock" without imitating wood or a brand.
struct HeadstockShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Helper: a point from normalized (0...1) fractions of the rect.
        func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + fx * rect.width, y: rect.minY + fy * rect.height)
        }

        var path = Path()

        // Start at the nut, left corner, and trace clockwise.
        path.move(to: p(0.32, 0.95))

        // Left side: bulge outward through the middle up to the left shoulder.
        path.addCurve(to: p(0.17, 0.13),
                      control1: p(0.09, 0.66),
                      control2: p(0.11, 0.28))

        // Top-left hump.
        path.addQuadCurve(to: p(0.35, 0.05), control: p(0.23, 0.03))
        // Center notch (the "open book" dip).
        path.addQuadCurve(to: p(0.50, 0.11), control: p(0.43, 0.11))
        // Top-right hump.
        path.addQuadCurve(to: p(0.65, 0.05), control: p(0.57, 0.11))
        // Right shoulder.
        path.addQuadCurve(to: p(0.83, 0.13), control: p(0.77, 0.03))

        // Right side: mirror of the left, down to the nut.
        path.addCurve(to: p(0.68, 0.95),
                      control1: p(0.89, 0.28),
                      control2: p(0.91, 0.66))

        // Nut edge: a slight concave-up curve back to the start.
        path.addQuadCurve(to: p(0.32, 0.95), control: p(0.50, 0.985))

        path.closeSubpath()
        return path
    }
}
