//
//  GKTypography.swift
//  GuitarKit
//
//  The app's type system: named font styles plus a "tabular figures" helper
//  for live-updating numbers.
//
//  TWO TYPEFACES, BY DESIGN:
//  - SF Pro (the default system font) for almost all text.
//  - SF Pro Rounded for the big "hero" note letter in the tuner — rounded
//    glyphs feel friendlier and more display-like for a single giant letter.
//  Both ship with iOS, so we get Dynamic Type (the user's preferred text
//  size) for free as long as we build fonts from the system text styles.
//

import SwiftUI

// Another empty `enum` used purely as a namespace (see GKColors for the why).
// Callers write `GKFont.heroNote` etc.
enum GKFont {

    // MARK: - Headings & body
    //
    // These start from SwiftUI's *semantic* text styles (`.largeTitle`,
    // `.title2`, `.body`, ...). Building on semantic styles means iOS scales
    // them with the user's Dynamic Type setting — crucial accessibility.
    // We layer on weight/design where we want a specific look.

    /// Big screen titles. SF Pro, bold.
    static let largeTitle = Font.system(.largeTitle, design: .default).weight(.bold)

    /// Section titles within a screen.
    static let title = Font.system(.title2, design: .default).weight(.semibold)

    /// Standard body copy.
    static let body = Font.system(.body, design: .default)

    /// Small captions / hints.
    static let caption = Font.system(.caption, design: .default)

    /// Labels for the rotary nav tabs — rounded to echo the playful hero font,
    /// and small/medium so five fit comfortably along the arc.
    static let navLabel = Font.system(.caption, design: .rounded).weight(.medium)

    // MARK: - Live numerics

    /// A monospaced-digit font for live-updating numbers (cents deviation,
    /// frequency in Hz, BPM). See `tabularNumbers()` below for *why* this
    /// matters; this is the font you'd attach to a number you want to read
    /// at a glance in a fixed-design style.
    static let liveNumeric = Font.system(.title3, design: .rounded)
        .monospacedDigit()
}

// MARK: - Hero note font (Dynamic-Type aware)

extension View {
    /// Apply the giant single-letter note font — the tuner "hero" glyph ("E",
    /// "A", …). SF Pro *Rounded*, bold, for a friendly display feel.
    ///
    /// Unlike a fixed point size, this SCALES with the user's Dynamic Type setting
    /// (via `@ScaledMetric`), so the single most important element on screen grows
    /// for people who need larger text instead of staying locked at 96 pt. We use
    /// a modifier (not a `static Font`) because `@ScaledMetric` reads the
    /// environment, which only a `View`/`ViewModifier` can do.
    func heroNoteFont() -> some View {
        modifier(HeroNoteFont())
    }
}

/// The hero-note font as a modifier so it can scale with Dynamic Type. Anchored
/// to `.largeTitle` so it tracks the same curve as the system's biggest style.
private struct HeroNoteFont: ViewModifier {
    /// 96 pt at the default text size; grows/shrinks with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 96

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .bold, design: .rounded))
    }
}

// MARK: - Tabular figures helper

extension View {
    /// Makes any numeric text use *tabular figures* (a.k.a. monospaced
    /// digits): every digit occupies the same fixed width.
    ///
    /// WHY THIS EXISTS:
    /// In a normal (proportional) font, a "1" is narrower than an "8". So a
    /// label that updates many times a second — like "+12¢" then "+8¢" then
    /// "−3¢" — visibly jitters left and right as digits change width. That's
    /// distracting on a tuner or metronome where numbers update constantly.
    /// Monospaced digits keep the text rock-steady.
    ///
    /// WHY A VIEW MODIFIER (the `func ... -> some View` on `View`):
    /// Extending `View` with our own method lets us write
    /// `Text("\(cents)¢").tabularNumbers()` anywhere, reading like built-in
    /// SwiftUI. `some View` means "this returns *a* view; the exact concrete
    /// type is hidden" — standard for composed modifiers.
    func tabularNumbers() -> some View {
        // `.monospacedDigit()` is the SwiftUI modifier that switches a font's
        // digits to fixed width while leaving letters proportional.
        self.monospacedDigit()
    }
}
