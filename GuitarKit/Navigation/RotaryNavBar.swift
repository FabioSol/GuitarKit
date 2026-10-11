//
//  RotaryNavBar.swift
//  GuitarKit
//
//  The custom rotary / arc bottom navigation — GuitarKit's signature navigation.
//
//  BEHAVIOR (from the PRD / issue #01):
//   - The tools ride a shallow arc (a "smile") near the bottom of the screen.
//     The *selected* tool sits at the apex (center); the others fan out to either
//     side, lower and dimmer the further they are from center.
//   - It's an INFINITE WHEEL: the tools are repeated around a full circle, so as
//     it rotates there is always a continuous run of tabs filling the visible arc
//     — spin past the last tool and the first comes round again.
//   - Tapping any tool spins it to the apex along the SHORTEST path.
//   - TAP ONLY — there is no drag gesture.
//   - REDUCE MOTION: the spin is instant (no rotation) — just a gentle emphasis
//     cross-fade.
//   - VOICEOVER: exactly five logical tabs, each announced as "Tuner, tab 1 of 5"
//     and the centered one as selected. (The visual repeats are hidden from
//     VoiceOver so it never reads a tool twice.)
//   - The chrome is Liquid Glass, grouped in a `GlassEffectContainer` so the tabs
//     blend/morph as they move.
//
//  HOW THE INFINITE WHEEL WORKS (the key idea):
//   - We place `copies` repetitions of the tool list evenly around a full circle,
//     giving `slotCount = tools.count * copies` SLOTS spaced `anglePerItem` apart
//     (so `slotCount * anglePerItem = 360`). Slot `k` shows `tools[k % count]`.
//   - A single accumulating `rotation` (degrees) spins the whole wheel. We only
//     DRAW the slots whose current angle is within the shallow visible arc near
//     the apex — typically about seven — and fade them out toward the edges so
//     they appear/disappear smoothly.
//   - Because the tools repeat every `count` slots, that visible run is always a
//     continuous, gap-free sequence of tools no matter how far we've spun. That's
//     the infinite-loop effect: there's no "end" to fall off.
//   - To select a tool we spin `rotation` by the shortest delta that brings the
//     NEAREST slot showing that tool up to the apex.
//

import SwiftUI
import UIKit

struct RotaryNavBar: View {

    // MARK: - Inputs

    /// The currently selected tool. `@Binding` means the parent owns this state
    /// and we read/write it through a two-way connection: when the user taps a
    /// tab we set `selection`, and the parent's screen switches.
    @Binding var selection: GKTool

    // MARK: - Wheel state

    /// The accumulated rotation of the whole wheel, in degrees. Spinning just
    /// keeps adding to it; `cos`/`sin` are periodic so it never needs wrapping.
    @State private var rotation: Double = 0

    /// Guards the very first layout so the initial selection appears at the apex
    /// instantly (no spin-in).
    @State private var hasAppeared = false

    /// Physical device orientation — tracked so icons can rotate to appear
    /// upright when the user holds the phone sideways on the Scales screen.
    @State private var deviceOrientation: UIDeviceOrientation = .portrait

    /// Degrees to rotate each icon. Non-zero only when Scales is active and
    /// the device is in landscape, so other tools are unaffected.
    private var iconAngle: Double {
        guard selection == .scales else { return 0 }
        switch deviceOrientation {
        case .landscapeLeft:  return 90
        case .landscapeRight: return -90
        default:              return 0
        }
    }

    // MARK: - Accessibility environment

    /// Reads the system "Reduce Motion" setting. When `true`, we don't spin; the
    /// selection change is instant.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Layout constants

    /// All tools, in a stable order. Computed once from the enum so the nav can
    /// never disagree with the list of tools.
    private let tools = GKTool.allCases

    /// How many times the tool list is repeated around the circle. With the
    /// flatter arc below, each item spans a smaller angle, so we need more copies
    /// to keep the full ring evenly populated for a smooth infinite spin.
    private let copies = 8

    /// The PURE wheel geometry (slot angles + shortest-spin math), unit-tested in
    /// `RotaryNavGeometryTests`. The view delegates all the trigonometry-adjacent
    /// math to it and keeps only the SwiftUI concerns (drawing, animation, a11y).
    private var geometry: RotaryNavGeometry {
        RotaryNavGeometry(toolCount: tools.count, copies: copies)
    }

    /// Total slots around the full circle (tools × copies).
    private var slotCount: Int { geometry.slotCount }

    /// Degrees between adjacent slots, sized so all the slots fill exactly 360°.
    /// Small enough that a handful of slots span the shallow visible arc.
    private var anglePerItem: Double { geometry.anglePerItem }

    /// How far (in degrees) either side of the apex we still DRAW a slot. Beyond
    /// this the tab has faded out. ~3 slots each side → about seven tabs on the
    /// arc at once.
    private var visibleHalfAngle: Double { anglePerItem * 3 + 2 }

    /// Radius of the circle the items ride on. A LARGE radius makes the arc very
    /// shallow (a gentle smile rather than a pronounced curve). Paired with
    /// `centerYOffset` so the visible slots stay on screen.
    private let radius: CGFloat = 480

    /// How far below the bar's bottom edge the circle's center sits. Combined
    /// with `radius` it turns the circle into a shallow bottom arc, and sets how
    /// far DOWN the tabs sit in the bar (larger = lower).
    private let centerYOffset: CGFloat = 415

    /// Diameter of each tab "coin."
    private let itemSize: CGFloat = 58

    var body: some View {
        // `GeometryReader` hands us the size of the space we're given so we can
        // anchor the wheel's center relative to the bar's width.
        GeometryReader { geo in
            // The circle's center: horizontally centered, pushed below the bottom
            // edge so we only see the top arc.
            let center = CGPoint(
                x: geo.size.width / 2,
                y: geo.size.height + centerYOffset
            )

            // For clean VoiceOver, we expose only ONE slot per tool — the one
            // currently nearest the apex. Precompute those representative slots.
            let reps = representativeSlots()

            // A plain ZStack so every coin is positioned in the SAME coordinate
            // space (the GeometryReader's), with no container relayout. We render
            // EVERY slot with a STABLE identity and just fade the off-arc ones to
            // zero — so spinning never inserts/removes views (which would pop and
            // jitter) and every coin animates along the same circle. Each coin
            // carries its own glass (we don't fuse them: the Liquid Glass *merge*
            // bends close coins onto a different curve, which looked wrong on a
            // tight arc).
            ZStack {
                ForEach(0..<slotCount, id: \.self) { k in
                    tabSlot(k, center: center, representativeSlots: reps)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // The bar occupies a fixed-height strip at the bottom; the arc reaches up
        // into it.
        .frame(height: 120)
        // Group the tabs under one accessibility container VoiceOver treats as a
        // tab bar.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
        // Place the wheel so the initial selection is centered — instantly.
        .onAppear {
            rotation = nearestRotation(for: selection)
            hasAppeared = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            refreshDeviceOrientation()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            refreshDeviceOrientation()
        }
        // Spin to follow selection changes that come from ELSEWHERE too (e.g. the
        // Circle-of-Fifths cross-links jumping to Chords/Scales).
        .onChange(of: selection) { _, _ in
            updateRotation(animated: hasAppeared)
        }
    }

    // MARK: - One slot

    /// Builds the tab coin for slot `k`, positioned on the arc by its current
    /// angle (slot angle + the wheel's rotation).
    private func tabSlot(_ k: Int, center: CGPoint, representativeSlots reps: [Int: Int]) -> some View {
        let tool = tools[k % tools.count]

        // Where this slot currently sits: its fixed slot angle plus the spin.
        // The apex is straight up (−90° in screen coordinates).
        let currentAngle = slotAngle(k) + rotation
        let radians = currentAngle * .pi / 180
        let position = CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )

        // Distance (shortest, in degrees) from the apex right now → drives the
        // fade/shrink so focus stays on the centered tool and edge tabs dissolve.
        let dist = abs(normalizeToShortest(currentAngle + 90))
        let proximity = max(0, 1 - dist / visibleHalfAngle)
        // Liquid Glass is the most expensive thing SwiftUI draws (it samples and
        // blurs what's behind it), and only ~7 of the slots are ever visible.
        // So only slots within 3 steps of the visible arc carry glass. Any spin
        // moves at most ~2.5 steps (the tools repeat every `tools.count`
        // slots), so no coin that can slide into view during an animation is
        // ever missing its glass — ~13 glass coins instead of all of them.
        let hasGlass = dist <= visibleHalfAngle + 3 * anglePerItem

        let isSelected = (tool == selection)
        // Only the representative slot for each tool is exposed to VoiceOver, so
        // it never announces a repeated tool. The visual repeats are hidden.
        let isAccessible = (reps[k % tools.count] == k)

        return Button {
            select(tool)
        } label: {
            tabLabel(for: tool, isSelected: isSelected, proximity: proximity, hasGlass: hasGlass)
        }
        .buttonStyle(.plain)
        .position(position)
        // Faded-out (off-arc) coins shouldn't intercept taps even though they
        // still exist in the hierarchy.
        .allowsHitTesting(proximity > 0.05)
        // --- Accessibility ---
        .accessibilityHidden(!isAccessible)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(tool.title), tab \(toolIndex(tool) + 1) of \(tools.count)")
        // Keep VoiceOver order = the tools' natural order, not the spun position.
        .accessibilitySortPriority(Double(tools.count - toolIndex(tool)))
    }

    /// The visual content of a tab: just the tool's icon inside a glass coin.
    /// (The tool name is still announced to VoiceOver via the button's label.)
    private func tabLabel(for tool: GKTool, isSelected: Bool, proximity: Double,
                          hasGlass: Bool) -> some View {
        Image(systemName: tool.systemImage)
            .font(.system(size: 24, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? GKColor.accent : GKColor.textSecondary)
            .rotationEffect(.degrees(iconAngle))
            .animation(.easeInOut(duration: 0.25), value: iconAngle)
            .frame(width: itemSize, height: itemSize)
        .modifier(CoinGlass(enabled: hasGlass))
        // Centered tab is largest + fully opaque; tabs toward the edges shrink
        // and fade to nothing (smooth enter/exit). Under Reduce Motion we keep a
        // constant size (no growth) but still fade for hierarchy.
        .scaleEffect(reduceMotion ? 1.0 : (0.7 + 0.3 * proximity))
        .opacity(proximity)
    }

    // MARK: - Geometry helpers

    /// The fixed angle of slot `k` (before the wheel's rotation): slot 0 is at the
    /// apex (−90°), each subsequent slot one step further round.
    private func slotAngle(_ k: Int) -> Double {
        geometry.slotAngle(k)
    }

    /// For each tool, the slot index currently CLOSEST to the apex — the one we
    /// expose to VoiceOver (keyed by the tool's natural index 0..<count).
    private func representativeSlots() -> [Int: Int] {
        var best: [Int: (slot: Int, dist: Double)] = [:]
        for k in 0..<slotCount {
            let ti = k % tools.count
            let dist = abs(normalizeToShortest(slotAngle(k) + rotation + 90))
            if best[ti] == nil || dist < best[ti]!.dist {
                best[ti] = (k, dist)
            }
        }
        return best.mapValues { $0.slot }
    }

    // MARK: - Selection / rotation logic

    /// Select `tool`: just set the binding. The `.onChange(of: selection)` above
    /// performs the spin (so taps and external selection changes share one path).
    private func select(_ tool: GKTool) {
        guard tool != selection else { return }
        selection = tool
    }

    /// Spin so the nearest slot showing `selection` reaches the apex.
    private func updateRotation(animated: Bool) {
        let target = nearestRotation(for: selection)
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                rotation = target
            }
        } else {
            rotation = target
        }
    }

    /// The rotation value (closest to the current one, so the spin is shortest)
    /// that brings some slot showing `tool` up to the apex.
    private func nearestRotation(for tool: GKTool) -> Double {
        geometry.nearestRotation(forToolIndex: toolIndex(tool), from: rotation)
    }

    /// A tool's natural index in the list (for "tab N of 5" + VoiceOver order).
    private func toolIndex(_ tool: GKTool) -> Int {
        tools.firstIndex(of: tool) ?? 0
    }

    private func refreshDeviceOrientation() {
        let o = UIDevice.current.orientation
        guard o.isLandscape || o.isPortrait else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            deviceOrientation = o
        }
    }

    /// Wraps any angle difference into (−180, 180] so we always take the shortest
    /// equivalent rotation — the heart of "shortest path + infinite wrap."
    private func normalizeToShortest(_ degrees: Double) -> Double {
        geometry.normalizeToShortest(degrees)
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

/// Glass for a nav coin — only when it can be seen (see `tabSlot`).
private struct CoinGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.gkGlass(in: Circle()) } else { content }
    }
}
