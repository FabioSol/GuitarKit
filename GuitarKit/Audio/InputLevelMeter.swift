//
//  InputLevelMeter.swift
//  GuitarKit
//
//  A simple, lively horizontal bar that fills with the current mic input level.
//  Its only job this slice is to PROVE audio flows end-to-end: play/speak and
//  the bar visibly reacts. The real tuner hero (headstock + deviation) replaces
//  this in later slices.
//

import SwiftUI

/// Draws a 0...1 level as a growing, accent-tinted bar with a soft glow.
struct InputLevelMeter: View {

    /// The current level to display, `0` (empty) … `1` (full). The parent
    /// passes the engine's smoothed `level` in here. A plain `let` because the
    /// view just renders whatever it's handed; the smoothing lives upstream.
    let level: Float

    var body: some View {
        // `GeometryReader` hands us the available size so the fill can be a
        // fraction of the *actual* track width rather than a guessed constant.
        GeometryReader { geometry in
            // The track (background) and the fill share a rounded shape.
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

            // `ZStack(alignment: .leading)` pins the fill to the left so it
            // grows rightward from the start of the track.
            ZStack(alignment: .leading) {
                // TRACK: a faint, recessed background showing the meter's extent.
                shape
                    .fill(GKColor.textSecondary.opacity(0.15))

                // FILL: width = level × trackWidth, clamped to 0...1 so a stray
                // out-of-range value can't overflow the track. `CGFloat(...)`
                // converts our `Float` level to the `CGFloat` SwiftUI sizes use.
                shape
                    .fill(
                        // A subtle accent gradient gives the bar some life.
                        LinearGradient(
                            colors: [GKColor.accent.opacity(0.7), GKColor.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(min(max(level, 0), 1)))
                    // A gentle glow that grows with the level, so loud moments
                    // feel energetic. Radius scales with level.
                    .shadow(color: GKColor.accent.opacity(0.6),
                            radius: CGFloat(level) * 8)
            }
            // Animate width changes so the bar glides rather than snapping each
            // time a new `level` arrives. The smoothing upstream already calms
            // the data; this just smooths the *drawing*.
            .animation(.easeOut(duration: 0.08), value: level)
        }
        // `GeometryReader` greedily fills space, so pin a sensible bar height.
        .frame(height: 24)
        // Expose to VoiceOver as an adjustable-looking value rather than a mute
        // shape. We describe it as a percentage so non-visual users get feedback
        // that the mic is hearing them.
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(min(max(level, 0), 1) * 100)) percent")
    }
}

#Preview {
    // A few static previews at different fill levels.
    VStack(spacing: 24) {
        InputLevelMeter(level: 0.1)
        InputLevelMeter(level: 0.5)
        InputLevelMeter(level: 0.9)
    }
    .padding()
    .background(GKColor.background)
}
