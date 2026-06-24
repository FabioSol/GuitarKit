//
//  HeroFlipModifier.swift
//  GuitarKit
//
//  A reusable "hero flip": a card that flips between a FRONT view and a BACK
//  view with a 3D rotation around the vertical (y) axis — like turning over a
//  playing card. The Tuner uses it to flip the targeted headstock hero (front)
//  to the chromatic readout (back) when the player toggles chromatic mode, so
//  switching "feels thematic" (PRD story 16).
//
//  ACCESSIBILITY (PRD: Reduce Motion → cross-fade): a spinning card is exactly
//  the kind of large motion that can be uncomfortable. When the system's
//  `accessibilityReduceMotion` is on, we DEGRADE the flip to a gentle opacity
//  cross-fade — same outcome (front swaps to back), no rotation.
//
//  WHY GENERIC (two @ViewBuilder closures + a Bool)?
//  This view knows nothing about tuners. It just takes "the thing to show on the
//  front", "the thing to show on the back", and "which side is up". Keeping it
//  content-agnostic means it's reusable anywhere and trivial to preview, and the
//  orchestrator wires the real front/back in from `TunerView`.
//

import SwiftUI

// MARK: - The flip container

/// Flips between `front` and `back` around the y-axis, driven by `isFlipped`.
///
/// `Front` and `Back` are generic placeholders for "whatever view you pass in".
/// Both must be `View`. The `@ViewBuilder` closures let callers write normal
/// SwiftUI bodies (`HeroFlip(isFlipped: x) { FrontView() } back: { BackView() }`).
struct HeroFlip<Front: View, Back: View>: View {

    /// Which face is showing: `false` = front, `true` = back. The parent owns
    /// this state (e.g. a chromatic-mode toggle) and flipping it animates the card.
    let isFlipped: Bool

    /// The two faces. Stored as closures we call inside `body` so SwiftUI builds
    /// each face lazily and re-renders it normally.
    private let front: Front
    private let back: Back

    /// The system "Reduce Motion" switch. `@Environment` reads a value SwiftUI
    /// injects from the device's accessibility settings; when it changes, the
    /// view re-evaluates, so the flip-vs-fade choice is always current.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `@ViewBuilder` on the parameters is what lets callers pass multi-statement
    /// view bodies (not just a single expression) for each face.
    init(
        isFlipped: Bool,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        self.isFlipped = isFlipped
        self.front = front()
        self.back = back()
    }

    var body: some View {
        // Two rendering paths that produce the SAME logical result (front ⇄ back),
        // chosen by the accessibility setting.
        Group {
            if reduceMotion {
                crossFade
            } else {
                rotatingCard
            }
        }
        // Animate whenever `isFlipped` changes. We pick a spring for the rotation
        // (a little physical "snap" as the card lands) and a plain ease for the
        // cross-fade. Tying the animation to `isFlipped` means only the flip is
        // animated, not unrelated redraws.
        .animation(
            reduceMotion ? .easeInOut(duration: 0.25)
                         : .spring(response: 0.55, dampingFraction: 0.8),
            value: isFlipped
        )
    }

    // MARK: - Reduce Motion path: cross-fade

    /// The comfortable fallback: simply fade whichever face is active in, and the
    /// other out. No rotation at all. We keep BOTH faces in the layout (one at
    /// zero opacity) so the card's size doesn't jump as they swap.
    private var crossFade: some View {
        ZStack {
            front.opacity(isFlipped ? 0 : 1)
            back.opacity(isFlipped ? 1 : 0)
        }
    }

    // MARK: - Default path: 3D rotation

    /// The real flip. The card rotates 0°→180° around its vertical axis. At the
    /// halfway point (90°) the card is edge-on (invisible), which is exactly when
    /// we swap which face is drawn — so you never see a mirror-imaged/back-to-front
    /// face, just front → (edge) → back.
    private var rotatingCard: some View {
        // The whole container's rotation. `back` shows once we're past halfway.
        let angle = isFlipped ? 180.0 : 0.0

        return ZStack {
            // FRONT face: visible for the first half of the turn (0°…90°), then
            // hidden so the back can take over.
            front
                .modifier(FlipFace(showing: !isFlipped))

            // BACK face: pre-rotated 180° so that when the container reaches 180°
            // the back reads the right way round (not mirror-imaged). Visible for
            // the second half of the turn.
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .modifier(FlipFace(showing: isFlipped))
        }
        // Rotate the entire stack around the y-axis. `perspective` adds a touch
        // of depth so it reads as a real 3D card rather than a flat squash.
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}

// MARK: - Per-face visibility helper

/// Hides a face once the card has rotated past edge-on, so only one side is ever
/// drawn. We fade `opacity` to 0 at the swap point rather than removing the view,
/// which keeps the layout (and thus the card's size) stable through the turn.
///
/// A small `ViewModifier` keeps the front/back call sites tidy and documents the
/// single concept ("this face is showing or it isn't") in one place.
private struct FlipFace: ViewModifier {
    /// Whether THIS face should currently be the visible one.
    let showing: Bool

    func body(content: Content) -> some View {
        content
            // Snap to 0 when not showing. The container's own animation drives the
            // rotation; this opacity flips at the midpoint so the hidden face never
            // bleeds through the edge-on moment.
            .opacity(showing ? 1 : 0)
    }
}

// MARK: - Convenience modifier-style API

extension View {
    /// Sugar so a caller can flip *this* view (the front) to some `back` view:
    ///
    ///     headstockHero
    ///         .heroFlip(isFlipped: isChromatic) { ChromaticReadoutView(reading: r) }
    ///
    /// Reads like built-in SwiftUI. Internally it just wraps `self` as the front
    /// face of a `HeroFlip`. Provided alongside the `HeroFlip` initializer so the
    /// orchestrator can use whichever spelling is clearer at the call site.
    func heroFlip<Back: View>(
        isFlipped: Bool,
        @ViewBuilder back: () -> Back
    ) -> some View {
        HeroFlip(isFlipped: isFlipped, front: { self }, back: back)
    }
}

// MARK: - Previews

#if DEBUG
/// A tiny stand-in card so we can see the flip without the real tuner views.
private struct DemoCard: View {
    let title: String
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(color)
            .overlay(Text(title).font(GKFont.title).foregroundStyle(.white))
            .frame(width: 240, height: 320)
    }
}

/// Interactive preview: tap to flip. (In Xcode's canvas, use the live/play mode
/// to tap.) Watch front → edge → back rotate; turn on Reduce Motion in the
/// simulator's accessibility settings to see it cross-fade instead.
private struct HeroFlipDemo: View {
    @State private var flipped = false
    var body: some View {
        VStack(spacing: 32) {
            HeroFlip(isFlipped: flipped) {
                DemoCard(title: "Front", color: GKColor.accent)
            } back: {
                DemoCard(title: "Back", color: GKColor.inTune)
            }
            Button("Flip") { flipped.toggle() }
                .font(GKFont.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GKColor.background)
        .preferredColorScheme(.dark)
    }
}

#Preview("Hero flip (tap Flip)") {
    HeroFlipDemo()
}
#endif
