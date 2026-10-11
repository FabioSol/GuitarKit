# Audit — Design System
**Scope:** GuitarKit/DesignSystem/GKColors.swift, GKGlass.swift, GKTypography.swift

**Health:** The token layer is well-structured, semantically named, and the adaptive(light:dark:) bridge is correct and built once per token (no per-render rebuild). The main weaknesses are accessibility: the glass opaque fallback can render chrome nearly invisible against the app background, the hero note font is locked at 96pt and ignores Dynamic Type, and the empty AccentColor asset lets system controls fall back to blue — which collides with the `flat` semantic. No design-system tests exist.

## Bugs & correctness
- [BUG|HIGH] `GKGlass.swift:86` — Opaque fallback fills the chrome shape with `GKColor.background`, the *same* token used as the screen background (e.g. `TunerHeroView.swift:149`, `MicDeniedView.swift:75`). When Increase Contrast / Reduce Transparency is on, an opaque pill placed on the app background becomes near-invisible — only the 1px `textSecondary.opacity(0.3)` hairline (itself low-contrast) separates it. This is the exact scenario (high-contrast a11y) the fallback exists to serve, so it inverts the intent. Fix: fill with a distinct elevated surface token (e.g. a `surfaceElevated` color that contrasts with `background`), and/or raise the stroke to a solid `textSecondary` (no 0.3 opacity) under contrast mode.
- [BUG|MED] `GKColors.swift` (whole file) / `Assets.xcassets/AccentColor.colorset` — The asset catalog AccentColor is empty (no color components defined), so SwiftUI's *default* tint (used implicitly by `Toggle`, `Button`, `Picker`, links, etc.) falls back to system blue. The code accent is purple (`GKColor.accent`), and blue is reserved for `flat`. Any control not explicitly tinted with `GKColor.accent` will show blue, contradicting the PRD's "blue means flat" rule and the single-accent design. Fix: define AccentColor.colorset with the same purple (light/dark variants) as `GKColor.accent`, or set `.tint(GKColor.accent)` at the app root.
- [BUG|LOW] `GKGlass.swift:89` — Fallback border uses `GKColor.textSecondary.opacity(0.3)`. `textSecondary` is `Color.secondary`, which is *already* a translucent dynamic color; multiplying by 0.3 yields an extremely faint hairline. Under Increase Contrast this border is the only thing delineating the control (see HIGH above) yet it gets fainter, not stronger. Fix: use an opaque, contrast-aware stroke color and full opacity in the fallback branch.

## Efficiency
- No per-render rebuilds: all color/font tokens are `static let`, resolved once. The `UIColor { traits in ... }` closure re-runs only on appearance change — correct and idiomatic.
- `GKGlass.swift:76-77` — `needsOpaqueFallback` is computed in `body`, i.e. per render of each glass element. Cheap (two environment reads + a bool), acceptable; no action needed.
- `GKGlass.swift:50` — `AnyShape(shape)` type-erases on every `gkGlass` call; negligible, and the comment justifies it. Nit only.

## Maintainability & practices
- [MED] `GKGlass.swift:97` — Glass `.tint(GKColor.accent.opacity(0.12))` is hardcoded; the opacity magic number (0.12) and the fallback's 0.3 are scattered literals. Consider centralizing glass tuning constants (tint opacity, stroke opacity, spacing default) so the "single seam to adjust" promised at `GKGlass.swift:110` is real.
- [MED] `GKTypography.swift:32` — `heroNote` is a fixed 96pt non-scaling font (see Test gaps / a11y below). Intentional per comment, but there is no `@ScaledMetric` or `.dynamicTypeSize(...)` cap, so it neither scales for low-vision users nor is protected from layout breakage at the largest accessibility sizes. At minimum document the deliberate non-scaling and ensure the hero view clamps/min-scales.
- [LOW] `GKColors.swift:119` — `adaptive` is `fileprivate`, so `GKColor.background`, `accent`, etc. are the only adaptive tokens possible. Fine, but if other modules ever need an adaptive surface they'll be tempted to duplicate the bridge. Acceptable as-is.
- [LOW] `GKTypography.swift:85-89` — `tabularNumbers()` is a thin alias for `.monospacedDigit()`. Good intention-revealing name and matches `liveNumeric` (which *also* applies `.monospacedDigit()` at `GKTypography.swift:64`); just note the redundancy when both are used on the same text (harmless).

## Test coverage gaps
- No tests exercise `GKColor`, `GKFont`, or `gkGlass`. The only consumer in tests is `HeroSnapshotGenerator.swift` (snapshot generation, not assertions).
- Missing: a test/snapshot proving the glass opaque fallback is visibly distinct from `GKColor.background` under Reduce Transparency + Increase Contrast (would have caught the HIGH bug).
- Missing: a Dynamic Type snapshot of the hero + body text at the largest accessibility size to verify no clipping/overlap (hero is fixed-size).
- Missing: a snapshot/contrast check confirming `sharp`/`flat`/`inTune` meet WCAG contrast on `GKColor.background` in both schemes.

## Top 3 priorities
1. Fix the glass opaque-fallback surface (GKGlass.swift:86,89) so chrome stays visibly distinct from the app background under Increase Contrast / Reduce Transparency — introduce an elevated surface token and a solid border in the fallback branch.
2. Populate AccentColor.colorset (or set `.tint(GKColor.accent)` at the root) so system controls stop defaulting to blue, which collides with the `flat` semantic.
3. Address hero Dynamic Type: clamp/min-scale the fixed 96pt `heroNote` and add an accessibility-size snapshot test so the most important element doesn't break for low-vision users.
