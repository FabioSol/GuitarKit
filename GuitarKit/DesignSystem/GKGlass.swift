//
//  GKGlass.swift
//  GuitarKit
//
//  Liquid Glass chrome wrappers (iOS 26).
//
//  WHAT IS "LIQUID GLASS"?
//  iOS 26 introduced a material called Liquid Glass: translucent, refractive
//  surfaces that pick up and bend the content behind them. Apple exposes it in
//  SwiftUI via:
//    - `.glassEffect(...)`    — applies the glass material to a view.
//    - `GlassEffectContainer` — groups several glass views so they can blend,
//      morph, and merge into one another when they move/animate near each
//      other (instead of each rendering its own isolated pane of glass).
//
//  HOUSE RULES (from the PRD):
//    - Glass lives on the *chrome / functional* layer only: the rotary nav,
//      pills, chips, toggles, sheets, the gear. NEVER on the hero content
//      (the tuner's note/headstock stays solid so its semantic colors keep
//      full contrast).
//    - NO glass-on-glass (don't nest glass inside glass).
//    - If the user turns on Reduce Transparency or Increase Contrast, glass
//      must fall back to an *opaque* surface so everything stays legible.
//
//  These wrappers centralize all of that so feature code just says
//  `.gkGlass()` and automatically gets the right behavior, including the
//  accessibility fallback.
//

import SwiftUI

// MARK: - Glass capsule / chrome surface modifier

extension View {
    /// Wraps a chrome element (nav bar, pill, chip, toggle…) in Liquid Glass,
    /// with an automatic opaque fallback for accessibility.
    ///
    /// - Parameter shape: the silhouette of the surface. Defaults to a
    ///   `Capsule`, which matches our pill/nav aesthetic, but callers can pass
    ///   any `Shape` (e.g. a `RoundedRectangle` for a sheet).
    ///
    /// Generic over `S: Shape`:
    /// `<S: Shape>` means this method works with *any* concrete shape type the
    /// caller supplies, while still being fully type-checked. That's Swift
    /// generics: write once, use with `Capsule`, `Circle`,
    /// `RoundedRectangle`, etc.
    func gkGlass<S: Shape>(in shape: S = Capsule()) -> some View {
        // We hand off to a custom `ViewModifier` (defined below) so the
        // accessibility-environment logic lives in one reusable place.
        modifier(GKGlassModifier(shape: AnyShape(shape)))
    }
}

/// A `ViewModifier` is SwiftUI's reusable "wrap a view in some styling" unit.
/// Conforming requires one method, `body(content:)`, which receives the view
/// being modified (`content`) and returns a new, decorated view.
private struct GKGlassModifier: ViewModifier {

    /// The outline of the glass surface. We store it type-erased as `AnyShape`
    /// so this struct doesn't itself need to be generic (keeps things simple
    /// for the environment reads below).
    let shape: AnyShape

    // `@Environment` reads a value out of SwiftUI's environment — the implicit
    // context every view sits inside. These two accessibility flags tell us
    // whether the user has asked the system to reduce translucency or raise
    // contrast. When either is on, we must drop the glass for an opaque fill.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        // Decide ONCE whether we're in "needs opaque fallback" mode:
        // either Reduce Transparency is on, OR the system reports increased
        // contrast (`colorSchemeContrast == .increased` corresponds to the
        // "Increase Contrast" accessibility setting).
        let needsOpaqueFallback =
            reduceTransparency || colorSchemeContrast == .increased

        if needsOpaqueFallback {
            // OPAQUE FALLBACK: a solid, ELEVATED surface that's visibly distinct
            // from the screen background (filling with the screen's own color
            // would make chrome vanish under Increase Contrast / Reduce
            // Transparency — the opposite of the point). `secondarySystemBackground`
            // is the system's elevated-surface color and adapts to light/dark +
            // high-contrast; we add a firmer border so the control's edge reads.
            content
                .background(
                    shape.fill(Color(uiColor: .secondarySystemBackground))
                )
                .overlay(
                    shape.stroke(GKColor.textSecondary.opacity(0.5), lineWidth: 1)
                )
        } else {
            // NORMAL PATH: real Liquid Glass.
            // `.glassEffect(_:in:)` applies the material clipped to `shape`.
            // `.regular` is the standard glass; `.tint(...)` lets the glass
            // carry a faint hint of our accent so chrome feels on-brand.
            content
                .glassEffect(.regular.tint(GKColor.accent.opacity(0.12)), in: shape)
        }
    }
}

// MARK: - Glass container wrapper

/// A thin, intention-revealing wrapper around iOS 26's `GlassEffectContainer`.
///
/// WHY WRAP IT?
/// 1. It documents *where* we intend multiple glass elements to blend/morph
///    together (the rotary nav is the prime example — tabs should merge as
///    they rotate, not look like separate glass coins).
/// 2. It gives us a single seam to adjust container-wide settings (like the
///    `spacing` that controls how close two glass shapes must be before they
///    visually merge) across the whole app.
///
/// `@ViewBuilder` on the initializer's `content` parameter lets callers pass a
/// normal SwiftUI view tree inside `{ ... }`, exactly like built-in containers
/// (`VStack { ... }`). `Content: View` is a generic so any view tree fits.
struct GKGlassContainer<Content: View>: View {

    /// How near two glass shapes must be (in points) before they start to
    /// fuse. Larger = they merge from farther apart.
    private let spacing: CGFloat

    /// The child views. Stored as a closure-built value typical of SwiftUI
    /// containers.
    private let content: Content

    init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        // `GlassEffectContainer` coordinates the glass rendering of all the
        // `.glassEffect` views inside it so they can blend and morph as a
        // group. Without it, each glass view is an island.
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}
