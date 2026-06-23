//
//  RotaryNavBar.swift
//  GuitarKit
//
//  The custom 5-item rotary / arc bottom navigation — GuitarKit's signature
//  navigation gesture.
//
//  BEHAVIOR (from the PRD / issue #01):
//   - All five tools are ALWAYS visible, spread along a shallow arc near the
//     bottom of the screen.
//   - The *selected* tool sits at the center/apex of the arc.
//   - Tapping any tool rotates the wheel so that tool travels to center,
//     always taking the SHORTEST path, with circular / infinite wrap (going
//     from the last item to the first spins forward a little, not all the way
//     back around).
//   - TAP ONLY — there is no drag gesture.
//   - REDUCE MOTION: instead of spinning, the bar cross-fades between states.
//   - VOICEOVER: each item is a proper tab announced as "Tuner, tab, 1 of 5"
//     and the centered one as selected.
//   - The chrome is Liquid Glass, grouped in a `GlassEffectContainer` so the
//     tabs blend/morph as they move.
//
//  HOW THE ROTATION MATH WORKS (the key idea):
//   - The five items occupy five evenly spaced "slots" around a circle, one
//     every `360 / 5 = 72` degrees.
//   - We keep a single `Double` called `rotation` (in degrees). The whole ring
//     is rotated by `rotation`, and each item is also pre-placed at its own
//     slot angle. When `rotation` is chosen so the selected item's slot lands
//     at the apex, that item is centered.
//   - To move selection, we DON'T snap `rotation` to a new absolute value
//     (that could spin the long way). Instead we compute the *signed shortest*
//     angular step between the old and new item and ADD it to `rotation`. That
//     guarantees the short path and naturally supports infinite wrap, because
//     `rotation` just keeps accumulating.
//

import SwiftUI

struct RotaryNavBar: View {

    // MARK: - Inputs

    /// The currently selected tool. `@Binding` means the parent owns this
    /// state and we read/write it through a two-way connection: when the user
    /// taps a tab we set `selection`, and the parent's screen switches.
    @Binding var selection: GKTool

    // MARK: - Internal animation state

    /// The accumulated rotation of the whole ring, in degrees. We START it at
    /// the value that centers the initial selection (done in `onAppear`).
    /// `@State` = view-local mutable storage that SwiftUI watches; changing it
    /// re-renders the view (and, inside `withAnimation`, animates the change).
    @State private var rotation: Double = 0

    /// Set to `true` after the first layout so we don't animate the very first
    /// placement (we want the initial center to appear instantly, not spin in).
    @State private var hasAppeared = false

    // MARK: - Accessibility environment

    /// Reads the system "Reduce Motion" setting. When `true`, we must NOT spin;
    /// we cross-fade instead. `@Environment` pulls this from SwiftUI's context.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Layout constants
    //
    // `private` so they're implementation details. Pulled out as named values
    // so the geometry is easy to read and tweak.

    /// All tools, in a stable order. Computed once from the enum so the nav can
    /// never disagree with the list of tools.
    private let tools = GKTool.allCases

    /// Degrees between adjacent items: a full circle divided by the count.
    private var anglePerItem: Double { 360.0 / Double(tools.count) }

    /// Radius of the circle the items ride on. Large + pushed down so only the
    /// top of the arc (a shallow smile) is on screen.
    private let radius: CGFloat = 240

    /// How far below the bottom edge the circle's center sits. Combined with
    /// `radius`, this is what turns a full circle into a shallow bottom arc.
    private let centerYOffset: CGFloat = 150

    /// Diameter of each tab "coin."
    private let itemSize: CGFloat = 64

    var body: some View {
        // `GeometryReader` hands us the size of the space we're given so we can
        // anchor the ring's center relative to the bar's width/height.
        GeometryReader { geo in
            // The circle's center: horizontally centered, pushed below the
            // bottom edge so we only see the top arc.
            let center = CGPoint(
                x: geo.size.width / 2,
                y: geo.size.height + centerYOffset
            )

            // Group all glass tabs so they blend/morph as one piece of glass
            // while the ring rotates (no glass-on-glass; the container itself
            // isn't glass — it just coordinates its children).
            GKGlassContainer(spacing: 28) {
                // `ForEach` builds one view per tool. We iterate over indices
                // so each item knows its slot number (0...4) and its "n of 5".
                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                    tabButton(for: tool, at: index, center: center)
                }
            }
        }
        // The bar occupies a fixed-height strip at the bottom; the arc reaches
        // up into it.
        .frame(height: 120)
        // Group the five tabs under one accessibility container that VoiceOver
        // treats as a tab bar.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
        // On first appearance, place the ring so the initial selection is
        // centered — instantly, with no animation.
        .onAppear {
            rotation = centeredRotation(for: selection)
            hasAppeared = true
        }
    }

    // MARK: - One tab

    /// Builds a single tappable tab coin, positioned on the arc.
    private func tabButton(for tool: GKTool, at index: Int, center: CGPoint) -> some View {
        // The item's own fixed slot angle around the circle. Item 0 is at the
        // apex (-90° in screen coordinates, where 0° points right and angles
        // grow clockwise), and each subsequent item is one step further round.
        let slotAngle = -90.0 + Double(index) * anglePerItem

        // The actual on-screen angle = its slot + the ring's current rotation.
        let currentAngle = slotAngle + rotation

        // Convert that polar angle into an (x, y) position on the circle.
        let radians = currentAngle * .pi / 180
        let position = CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )

        // Is this the centered/selected tab? Used for emphasis + a11y.
        let isSelected = (tool == selection)

        // How far (in degrees, shortest direction) this item is from the apex
        // right now. We use it to fade/shrink items as they move away from
        // center, so the focus stays on the centered tool.
        let distanceFromCenter = abs(shortestDelta(from: currentAngle, to: -90.0))
        let proximity = max(0, 1 - distanceFromCenter / 90.0) // 1 at center → 0 at 90° away

        return Button {
            // TAP ACTION: move this tool to center via the shortest path.
            select(tool)
        } label: {
            tabLabel(for: tool, isSelected: isSelected, proximity: proximity)
        }
        // Remove the default button styling so our custom coin shows through.
        .buttonStyle(.plain)
        // Place the coin at its computed point on the arc.
        .position(position)
        // VOICEOVER SEMANTICS:
        // - `.isButton` + `.isSelected` so it reads as a selectable tab.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // - A spoken label like "Tuner, tab 1 of 5". VoiceOver appends
        //   "selected" automatically when the `.isSelected` trait is present.
        .accessibilityLabel("\(tool.title), tab \(index + 1) of \(tools.count)")
        // Keep tabs in their natural reading order for VoiceOver regardless of
        // their on-screen rotation, by sorting on the slot index.
        .accessibilitySortPriority(Double(tools.count - index))
    }

    /// The visual content of a tab: icon + label inside a glass coin.
    private func tabLabel(for tool: GKTool, isSelected: Bool, proximity: Double) -> some View {
        VStack(spacing: 4) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
            Text(tool.shortTitle)
                .font(GKFont.navLabel)
                .lineLimit(1)
        }
        // Selected tab glows in the accent color; others use secondary text.
        .foregroundStyle(isSelected ? GKColor.accent : GKColor.textSecondary)
        .frame(width: itemSize, height: itemSize)
        // Wrap each coin in Liquid Glass (capsule shape). Because they live in
        // a `GlassEffectContainer`, adjacent coins blend as they move.
        .gkGlass(in: Circle())
        // Emphasize the centered tab: slightly larger, fully opaque; items
        // further from center shrink and dim. Under Reduce Motion we skip the
        // scaling so nothing "moves," but still dim for hierarchy.
        .scaleEffect(reduceMotion ? 1.0 : (0.85 + 0.25 * proximity))
        .opacity(0.55 + 0.45 * proximity)
    }

    // MARK: - Selection / rotation logic

    /// Moves `tool` to the center, choosing how to animate based on Reduce
    /// Motion. Called from a tab's tap action.
    private func select(_ tool: GKTool) {
        guard tool != selection else { return } // already centered; nothing to do

        if reduceMotion {
            // REDUCE MOTION PATH: no spin. We snap the rotation to the new
            // centered value (instant) but wrap the *selection* change in a
            // gentle cross-fade so the emphasis shifts without rotary motion.
            rotation = centeredRotation(for: tool)
            withAnimation(.easeInOut(duration: 0.25)) {
                selection = tool
            }
        } else {
            // NORMAL PATH: spin along the shortest arc.
            // Compute the signed shortest angular step from the currently
            // centered tool to the tapped one, then ADD it to `rotation`.
            // Adding (rather than assigning an absolute) is what makes the spin
            // take the short way and wrap infinitely.
            let step = shortestStepBetween(selection, and: tool)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                rotation += step
                selection = tool
            }
        }
    }

    /// The absolute `rotation` value that places `tool` at the apex, ignoring
    /// shortest-path concerns. Used only for the initial placement and the
    /// Reduce-Motion snap (where instant assignment is fine).
    private func centeredRotation(for tool: GKTool) -> Double {
        // Item at `index` sits at slot `-90 + index*step`. To bring it to the
        // apex (-90), the ring must rotate by `-index*step`.
        let index = tools.firstIndex(of: tool) ?? 0
        return -Double(index) * anglePerItem
    }

    /// Signed shortest angular distance (in degrees) needed to move the
    /// currently centered `from` tool's position to the `to` tool's slot.
    ///
    /// We work in "index space": each item is `anglePerItem` degrees apart, so
    /// the raw step is `(toIndex - fromIndex) * anglePerItem`, then we
    /// normalize into the range (−180, 180] so we always rotate the short way.
    private func shortestStepBetween(_ from: GKTool, and to: GKTool) -> Double {
        let fromIndex = tools.firstIndex(of: from) ?? 0
        let toIndex = tools.firstIndex(of: to) ?? 0
        // We want the wheel to move so `to` reaches center. Moving `to` from
        // its slot to the apex means rotating by the negative of its index
        // delta relative to `from`.
        let rawDelta = Double(toIndex - fromIndex) * anglePerItem
        return normalizeToShortest(-rawDelta)
    }

    /// Shortest signed delta to get from angle `a` to angle `b`, in (−180,180].
    private func shortestDelta(from a: Double, to b: Double) -> Double {
        normalizeToShortest(b - a)
    }

    /// Wraps any angle difference into the range (−180, 180] so "+350°" becomes
    /// "−10°" — i.e. always the shortest equivalent rotation. This is the heart
    /// of the "shortest path + infinite wrap" behavior.
    private func normalizeToShortest(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360) // into (−360, 360)
        if d > 180 { d -= 360 }      // e.g. 350 → −10
        if d <= -180 { d += 360 }    // e.g. −350 → 10
        return d
    }
}

#Preview {
    // A tiny stateful wrapper so the preview can drive the binding.
    struct PreviewHost: View {
        @State private var selection: GKTool = .tuner
        var body: some View {
            ZStack {
                GKColor.background.ignoresSafeArea()
                VStack {
                    Spacer()
                    Text("Selected: \(selection.title)")
                        .foregroundStyle(GKColor.textPrimary)
                    Spacer()
                    RotaryNavBar(selection: $selection)
                }
            }
        }
    }
    return PreviewHost()
}
