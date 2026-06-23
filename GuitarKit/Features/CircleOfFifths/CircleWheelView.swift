//
//  CircleWheelView.swift
//  GuitarKit — Circle of Fifths feature
//
//  The interactive wheel: an OUTER ring of the twelve major keys and an INNER
//  ring of their relative minors. It is a *selector only* (PRD's circle-of-fifths
//  decision): tapping a segment tells the view model to select that key. All the
//  "what does this key mean" detail lives in the separate details panel — this
//  keeps tap intent unambiguous (you tap the wheel to *choose*, never to *act*).
//
//  HOW THE WHEEL IS DRAWN:
//  We place twelve "spokes" (seats) evenly around a circle. Seat 0 (C / A minor)
//  is at the top; each subsequent seat is 30° further clockwise. For each seat we
//  draw two tappable buttons stacked radially: the major key further out, its
//  relative minor further in. The whole wheel is then `.rotationEffect(...)`-ed
//  by the view model's `rotationDegrees` so the selected seat swings to the top.
//
//  REDUCE MOTION:
//  When the user has Reduce Motion on we must NOT spin the wheel (PRD
//  accessibility rule). We detect that with `@Environment(\.accessibilityReduce
//  Motion)` and, in that mode, simply skip the rotation animation — the selected
//  segment is still highlighted in the accent colour, which is the non-motion
//  signal of "this is selected."
//

import SwiftUI

struct CircleWheelView: View {

    /// The shared view model. `@Bindable` would be needed only if we passed
    /// bindings down; here we just read state and call methods, so a plain `let`
    /// reference to the `@Observable` object is enough — SwiftUI still tracks the
    /// properties we read inside `body` and re-renders on change.
    let viewModel: CircleOfFifthsViewModel

    /// Reads the system "Reduce Motion" accessibility setting out of the
    /// environment. `true` → the user wants minimal animation, so we won't spin.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // `GeometryReader` hands us the actual size we've been given so the wheel
        // scales to whatever space the layout allows (it stays a circle by using
        // the smaller of width/height). It's the standard way to do "draw me
        // relative to my container's size" in SwiftUI.
        GeometryReader { geometry in
            // The wheel is a square circle centred in the available space; use
            // the smaller dimension so it never gets clipped.
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2

            // Ring radii: the major keys ride near the outer edge, the minors on
            // an inner band. These fractions are tuned so both rings have room
            // for a readable label.
            let majorRadius = radius * 0.82
            let minorRadius = radius * 0.52

            ZStack {
                // A faint guide circle so the wheel reads as a dial even before
                // anything is selected. Purely decorative.
                Circle()
                    .stroke(GKColor.textSecondary.opacity(0.15), lineWidth: 1)
                    .frame(width: majorRadius * 2 + 44,
                           height: majorRadius * 2 + 44)

                // The twelve seats. We iterate seat indices 0..<12 and place a
                // major + minor button at each. `ForEach(0..<12)` over a constant
                // range is fine here (SwiftUI requires constant ranges for the
                // integer overload, which this is).
                ForEach(0..<CircleOfFifths.count, id: \.self) { seat in
                    seatSegments(seat: seat,
                                 majorRadius: majorRadius,
                                 minorRadius: minorRadius,
                                 center: CGPoint(x: side / 2, y: side / 2))
                }
            }
            .frame(width: side, height: side)
            // Centre the square wheel within whatever (possibly non-square) space
            // the GeometryReader reported.
            .frame(width: geometry.size.width, height: geometry.size.height)
            // THE ROTATION. The wheel spins around its centre to the view model's
            // target rotation. Under Reduce Motion we still apply the rotation
            // value (so the home seat is logically on top) but the change is not
            // animated — see `.animation` below.
            .rotationEffect(.degrees(viewModel.rotationDegrees))
            // Animate the rotation ONLY when Reduce Motion is off. Passing `nil`
            // as the animation disables it, giving an instant, motion-free jump.
            .animation(reduceMotion ? nil
                                    : .spring(response: 0.6, dampingFraction: 0.8),
                       value: viewModel.rotationDegrees)
        }
        // Keep the wheel square in the layout so it doesn't stretch.
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - One seat (a major button + its relative-minor button)

    /// Builds the two buttons for a single seat, positioned around the wheel.
    ///
    /// `@ViewBuilder` lets this helper return a small view tree (two buttons) the
    /// same way `body` does. Pulling it out keeps `body` readable.
    @ViewBuilder
    private func seatSegments(seat: Int,
                              majorRadius: CGFloat,
                              minorRadius: CGFloat,
                              center: CGPoint) -> some View {
        // The major and minor key sharing this spoke.
        let majorKey = CircleOfFifths.majorKeys[seat]
        let minorKey = CircleOfFifths.minorKeys[seat]

        // The angle of this seat, measured clockwise from the top (12 o'clock).
        // Seat 0 → 0°, seat 1 → 30°, … We convert to a position with `offset(at:)`.
        let angle = Angle.degrees(Double(seat) * 360.0 / Double(CircleOfFifths.count))

        // Outer ring: the major key.
        keyButton(for: majorKey, isMajor: true)
            .position(offset(at: angle, radius: majorRadius, center: center))

        // Inner ring: the relative minor.
        keyButton(for: minorKey, isMajor: false)
            .position(offset(at: angle, radius: minorRadius, center: center))
    }

    // MARK: - A single tappable key segment

    /// One key as a labelled, selectable button — the VoiceOver-friendly unit the
    /// PRD requires (each segment is a labelled button with a selected trait).
    private func keyButton(for key: Key, isMajor: Bool) -> some View {
        // Is this the currently selected key? Drives the accent highlight, which
        // is the *non-motion* "selected" signal (essential under Reduce Motion).
        let isSelected = key == viewModel.selectedKey

        return Button {
            // Tapping selects the key. All the rotation + (future) audio logic
            // lives in the view model so this stays a one-liner.
            viewModel.select(key)
        } label: {
            Text(key.tonic.name)
                // Major keys are visually a touch larger/bolder than the inner
                // minors, mirroring a printed circle-of-fifths diagram.
                .font(isMajor ? GKFont.title : GKFont.body)
                .foregroundStyle(isSelected ? Color.white : GKColor.textPrimary)
                .frame(width: isMajor ? 46 : 38,
                       height: isMajor ? 46 : 38)
                .background(
                    Circle()
                        // Selected → solid accent; otherwise a faint surface so
                        // the segment still reads as a tappable token.
                        .fill(isSelected
                              ? GKColor.accent
                              : GKColor.textSecondary.opacity(0.12))
                )
                // Counter-rotate each label by the wheel's rotation so the text
                // stays upright/readable even as the wheel spins. (Without this,
                // labels would tilt with the dial.)
                .rotationEffect(.degrees(-viewModel.rotationDegrees))
        }
        // `.plain` strips the default button tint/animation so our custom circle
        // styling shows through cleanly.
        .buttonStyle(.plain)
        // VOICEOVER SEMANTICS (PRD: each segment is a labelled, selectable
        // button). We give a spoken label like "C major" and mark the selected
        // one with the `.isSelected` trait so VoiceOver announces "selected."
        .accessibilityLabel(key.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Geometry helper

    /// Convert a seat angle (clockwise from the top) + a radius into a point in
    /// the wheel's coordinate space.
    ///
    /// THE TRIG:
    /// Standard maths angles start at 3 o'clock and go anticlockwise, but we want
    /// 0° at the TOP (12 o'clock) and to increase CLOCKWISE (like a clock and
    /// like the printed circle of fifths). The conversion is:
    ///   x = center.x + radius * sin(θ)
    ///   y = center.y − radius * cos(θ)
    /// Using sin for x and −cos for y rotates the usual circle so 0° lands at the
    /// top and positive θ sweeps clockwise.
    private func offset(at angle: Angle, radius: CGFloat, center: CGPoint) -> CGPoint {
        let radians = angle.radians
        let x = center.x + radius * CGFloat(sin(radians))
        let y = center.y - radius * CGFloat(cos(radians))
        return CGPoint(x: x, y: y)
    }
}
