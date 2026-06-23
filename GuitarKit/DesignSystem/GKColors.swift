//
//  GKColors.swift
//  GuitarKit
//
//  The app's color palette ("color tokens"), all in one place.
//
//  WHY A SINGLE FILE OF TOKENS?
//  Instead of sprinkling `Color.red` or `Color(red: 0.9, ...)` all over the
//  app, we name our colors by *meaning* ("sharp", "flat", "inTune", "accent").
//  This is called a *semantic* palette. The benefit: if we later decide
//  "sharp" should be a slightly different red, we change it in one spot and
//  the whole app updates. It also makes the code read like English:
//  `.foregroundStyle(GKColor.sharp)` says *what* the color means, not which
//  RGB it happens to be today.
//
//  DARK-FIRST, LIGHT-SUPPORTED
//  The PRD wants a dark-first design that still works in light mode. SwiftUI
//  gives us two tools for this:
//    1. System "dynamic" colors (like `Color.primary`) that automatically
//       adapt to light/dark — we lean on these for text/background chrome.
//    2. For our custom brand/semantic colors we build a color that resolves
//       differently per appearance using an initializer that inspects the
//       trait environment. That's the `adaptive(...)` helper below.
//

import SwiftUI

// `enum` used as a namespace:
// A Swift `enum` with no cases can never be instantiated, which makes it a
// tidy "namespace" — a bag of related static values. We're NOT using it as a
// list of choices here; we're using it purely so we can write
// `GKColor.sharp` and group all color tokens under one name. (A `struct`
// could do this too, but an empty `enum` makes it impossible to accidentally
// create an instance, which signals "this is just a container.")
enum GKColor {

    // MARK: - Brand accent

    /// The single signature color of the app: a purple/violet that leans
    /// toward magenta. The PRD is explicit that it must stay *away from
    /// indigo/blue*, because blue already means "flat" in the tuner — an
    /// indigo accent could read as "you're flat," which would be confusing.
    ///
    /// We hand-pick the RGB rather than using the system purple so we control
    /// exactly how magenta-leaning it is. We give it a slightly brighter
    /// variant in dark mode (so it glows against black) and a slightly deeper
    /// one in light mode (so it stays legible on white).
    static let accent = adaptive(
        light: Color(red: 0.55, green: 0.16, blue: 0.78), // deeper violet for white backgrounds
        dark:  Color(red: 0.72, green: 0.36, blue: 0.95)  // brighter magenta-violet for dark backgrounds
    )

    // MARK: - Tuning semantic colors
    //
    // These three encode the tuner's core feedback. IMPORTANT (accessibility):
    // color is NEVER the only signal in GuitarKit — position, shape, motion,
    // and haptics also convey state, per the PRD. These tokens are the color
    // *layer* of that multi-channel feedback, not a standalone indicator.

    /// You are SHARP (too high) — turn the peg down. Red.
    static let sharp = adaptive(
        light: Color(red: 0.86, green: 0.18, blue: 0.18),
        dark:  Color(red: 1.00, green: 0.36, blue: 0.34)
    )

    /// You are FLAT (too low) — turn the peg up. Blue.
    static let flat = adaptive(
        light: Color(red: 0.12, green: 0.42, blue: 0.90),
        dark:  Color(red: 0.36, green: 0.62, blue: 1.00)
    )

    /// You are IN TUNE — the happy state. Green.
    static let inTune = adaptive(
        light: Color(red: 0.13, green: 0.62, blue: 0.30),
        dark:  Color(red: 0.30, green: 0.85, blue: 0.46)
    )

    // MARK: - Surfaces & text
    //
    // For the everyday chrome (backgrounds, labels) we mostly defer to the
    // system's dynamic colors so we inherit Apple's carefully tuned contrast
    // for light/dark and high-contrast accessibility settings for free.

    /// The app's base background. We provide our own near-black for dark mode
    /// (true black can look harsh and shows OLED banding) and the system
    /// background for light mode.
    static let background = adaptive(
        light: Color(red: 0.97, green: 0.97, blue: 0.98),
        dark:  Color(red: 0.05, green: 0.05, blue: 0.07)
    )

    /// Primary text/icon color. `Color.primary` already adapts to appearance
    /// and to accessibility contrast settings, so we just alias it with a
    /// project-specific name.
    static let textPrimary = Color.primary

    /// Secondary/dimmed text (hints, captions). Also a system dynamic color.
    static let textSecondary = Color.secondary
}

// MARK: - Adaptive color helper

extension GKColor {
    /// Builds a single `Color` that automatically shows `light` in light mode
    /// and `dark` in dark mode.
    ///
    /// HOW IT WORKS:
    /// `UIColor` (the older UIKit color type) has an initializer that takes a
    /// closure receiving the current `UITraitCollection` (the environment's
    /// traits, including `userInterfaceStyle` = light/dark). iOS calls that
    /// closure whenever the appearance changes and re-resolves the color.
    /// We pick the right SwiftUI `Color`, convert it to `UIColor`, and return
    /// it. Finally we wrap the resulting dynamic `UIColor` back into a SwiftUI
    /// `Color`. SwiftUI doesn't (yet) expose a first-class "two-color"
    /// initializer, so bridging through `UIColor` is the standard trick.
    ///
    /// `private` because callers outside this file should use the named tokens
    /// above, not build ad-hoc adaptive colors.
    fileprivate static func adaptive(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            // `traits.userInterfaceStyle` tells us which appearance is active.
            // `.dark` → use the dark variant; anything else → the light one.
            switch traits.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
    }
}
