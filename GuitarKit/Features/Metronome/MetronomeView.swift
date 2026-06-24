//
//  MetronomeView.swift
//  GuitarKit — Metronome tool
//
//  The Metronome screen: a big circular tempo dial you drag to set the BPM,
//  ringed by one dot per beat that lights as the click plays, with a play/stop
//  button, a tap-tempo button, and ±1 steppers as alternate inputs. All the
//  state and audio live in `MetronomeViewModel`; this view is just the drawing
//  and the gestures.
//
//  THE DIAL'S GESTURES (two ways to "turn" it, both wired below):
//  1. VERTICAL DRAG (the primary one): drag UP to speed up, DOWN to slow down.
//     This is the most discoverable — it matches the mental model of a fader.
//  2. ROTARY DRAG: dragging in a circle around the dial also nudges the tempo by
//     the angle you sweep, like turning a physical knob.
//  We track the drag incrementally (the change since the last drag event) so the
//  two feel natural and never "jump."
//
//  ACCESSIBILITY:
//  The dial is a single VoiceOver element with an ADJUSTABLE action, so a
//  VoiceOver user swipes up/down to change the tempo ±1 BPM, and hears the
//  current BPM read out via `.accessibilityValue`. That's the non-visual
//  equivalent of the drag gesture.
//

import SwiftUI

struct MetronomeView: View {

    /// The screen owns its view model. `@State` keeps the same instance alive
    /// across re-renders (SwiftUI re-runs `body` constantly; the model must not
    /// be recreated each time).
    @State private var model = MetronomeViewModel()

    // MARK: - Drag tracking
    //
    // To turn a drag into a TEMPO CHANGE we need the *incremental* movement
    // since the previous gesture callback, not the total translation. We remember
    // the last vertical position and the last angle, and on each update apply
    // only the delta. Both reset when the drag ends.

    /// The vertical position (in points) at the previous drag callback, or `nil`
    /// before a drag begins. Used for the vertical-drag mapping.
    @State private var lastDragY: CGFloat?

    /// The angle (in radians) from the dial's center at the previous drag
    /// callback, or `nil` before a drag begins. Used for the rotary mapping.
    @State private var lastAngle: Double?

    /// The on-screen diameter of the dial. A constant keeps the trig (dot
    /// placement, center math) in one place.
    private let dialSize: CGFloat = 260

    var body: some View {
        ZStack {
            GKColor.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Metronome")
                    .font(GKFont.largeTitle)
                    .foregroundStyle(GKColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                dial
                Spacer()
                transportButton
                tapAndSteppers
                Spacer()
            }
            .padding()
        }
        // Release the audio session and stop the click when leaving the tool.
        .onDisappear { model.shutdown() }
    }

    // MARK: - The dial

    /// The circular tempo dial: an outer ring, the beat-ring dots placed with
    /// trig around it, and the big BPM number in the center. The whole stack is
    /// one draggable, VoiceOver-adjustable control.
    private var dial: some View {
        ZStack {
            // The ring itself — a stroked circle. We tint it with the accent so
            // the dial reads as the primary, "live" control on the screen.
            Circle()
                .stroke(GKColor.accent.opacity(0.35), lineWidth: 10)
                .frame(width: dialSize, height: dialSize)

            // One dot per beat, evenly spaced around the ring. The downbeat (beat
            // 0) is always the accent color; the currently-playing beat lights up
            // bright; the rest are dim.
            beatRing

            // The BPM number, centered. SF Rounded + tabular figures so it reads
            // like a display readout and doesn't jitter as digits change width.
            VStack(spacing: 2) {
                Text("\(Int(model.bpm))")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .tabularNumbers()
                    .foregroundStyle(GKColor.textPrimary)
                Text("BPM")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
            }
        }
        .frame(width: dialSize, height: dialSize)
        // The whole dial is the drag surface. `contentShape` makes the full
        // circle area hit-testable (not just the drawn strokes), so a drag
        // starting anywhere inside the dial counts.
        .contentShape(Circle())
        .gesture(dialDrag)
        // --- VoiceOver: expose the dial as an adjustable control. ---
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(Int(model.bpm)) BPM")
        .accessibilityAdjustableAction { direction in
            // Swipe up = increment, swipe down = decrement, ±1 BPM each.
            switch direction {
            case .increment: model.nudge(by: 1)
            case .decrement: model.nudge(by: -1)
            @unknown default: break   // future directions: ignore safely
            }
        }
    }

    /// The ring of beat dots. Each dot sits at its angle around the dial; the
    /// downbeat is accent-colored, the active beat glows, the rest are faint.
    private var beatRing: some View {
        // The radius at which dots sit: just inside the stroked ring.
        let radius = dialSize / 2 - 6

        return ZStack {
            ForEach(0..<model.beatsPerBar, id: \.self) { beat in
                let isDownbeat = beat == 0
                let isActive = beat == model.currentBeat && model.isPlaying

                Circle()
                    .fill(dotColor(isDownbeat: isDownbeat, isActive: isActive))
                    .frame(width: isDownbeat ? 16 : 12,
                           height: isDownbeat ? 16 : 12)
                    // Place the dot using trig. We start at the TOP (12 o'clock,
                    // −90°) and go clockwise, so beat 0 sits at the top where a
                    // downbeat naturally "reads." `offset` shifts from center.
                    .offset(dotOffset(beat: beat, radius: radius))
                    // A subtle pop when a beat lights up.
                    .animation(.easeOut(duration: 0.12), value: model.currentBeat)
            }
        }
    }

    /// The color of a beat dot given its role and whether it's currently playing.
    private func dotColor(isDownbeat: Bool, isActive: Bool) -> Color {
        if isActive {
            // The lit beat: full brightness. Downbeat stays accent; others go
            // to the friendly "in tune" green so the moving light is obvious.
            return isDownbeat ? GKColor.accent : GKColor.inTune
        }
        // Idle dots: the downbeat keeps a dim accent so you can always see where
        // "1" is; the rest are faint secondary dots.
        return isDownbeat ? GKColor.accent.opacity(0.7)
                          : GKColor.textSecondary.opacity(0.4)
    }

    /// The (x, y) offset of beat `beat`'s dot from the dial center, placing dots
    /// evenly around the circle starting at the top and going clockwise.
    private func dotOffset(beat: Int, radius: CGFloat) -> CGSize {
        // Evenly divide the full circle (2π) among the beats. Subtract π/2 to
        // rotate the start point from 3 o'clock (the math default) up to 12.
        let anglePerBeat = (2 * Double.pi) / Double(model.beatsPerBar)
        let angle = anglePerBeat * Double(beat) - Double.pi / 2
        return CGSize(width: radius * cos(angle),
                      height: radius * sin(angle))
    }

    // MARK: - The dial drag gesture (vertical + rotary)

    /// One `DragGesture` driving BOTH mappings. We use `minimumDistance: 0` so a
    /// drag that begins anywhere in the dial is tracked immediately.
    private var dialDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                applyVerticalDrag(value)
                applyRotaryDrag(value)
            }
            .onEnded { _ in
                // Forget the anchors so the NEXT drag starts fresh rather than
                // jumping by the gap between gestures.
                lastDragY = nil
                lastAngle = nil
            }
    }

    /// VERTICAL mapping: moving the finger UP (y decreases) raises the BPM. We
    /// apply the change since the last callback, scaled so a full-screen drag
    /// spans a usable tempo range without being twitchy.
    private func applyVerticalDrag(_ value: DragGesture.Value) {
        let y = value.location.y
        defer { lastDragY = y }
        guard let previous = lastDragY else { return }   // first event: just anchor

        // Upward movement = negative dy in screen coordinates, so NEGATE to make
        // up = faster. `pointsPerBPM` controls sensitivity: ~3 points per BPM
        // feels precise without being sluggish.
        let pointsPerBPM: CGFloat = 3
        let deltaBPM = Double(-(y - previous) / pointsPerBPM)
        model.nudge(by: deltaBPM)
    }

    /// ROTARY mapping: dragging in a circle around the center turns the dial like
    /// a knob. We measure the angle from the center and apply the angular change
    /// since the last callback (clockwise = faster).
    private func applyRotaryDrag(_ value: DragGesture.Value) {
        // Vector from the dial center to the finger. The gesture's coordinate
        // space is the dial itself, so the center is (dialSize/2, dialSize/2).
        let center = CGPoint(x: dialSize / 2, y: dialSize / 2)
        let dx = value.location.x - center.x
        let dy = value.location.y - center.y

        // Ignore touches right at the center — the angle there is meaningless and
        // would produce wild jumps.
        guard dx * dx + dy * dy > 100 else { return }

        let angle = atan2(Double(dy), Double(dx))   // radians, −π…π
        defer { lastAngle = angle }
        guard let previous = lastAngle else { return }   // first event: just anchor

        // The raw angular change, normalized into −π…π so crossing the ±π seam
        // (e.g. just past 9 o'clock) doesn't register as a giant jump.
        var delta = angle - previous
        if delta > .pi { delta -= 2 * .pi }
        if delta < -(.pi) { delta += 2 * .pi }

        // Map a full turn (2π) onto a sensible tempo span. Clockwise (positive
        // delta in screen coords, where y points down) = faster.
        let bpmPerTurn = 60.0
        model.nudge(by: delta / (2 * .pi) * bpmPerTurn)
    }

    // MARK: - Transport + alternate inputs

    /// The single play/stop button. Its icon and tint reflect the running state.
    private var transportButton: some View {
        Button {
            model.toggle()
        } label: {
            Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Circle().fill(GKColor.accent))
        }
        .accessibilityLabel(model.isPlaying ? "Stop" : "Play")
    }

    /// The tap-tempo button plus the ±1 steppers, on one row.
    private var tapAndSteppers: some View {
        HStack(spacing: 20) {
            // −1 BPM.
            stepperButton(symbol: "minus", label: "Decrease tempo") {
                model.nudge(by: -1)
            }

            // Tap repeatedly to set the tempo from your taps.
            Button {
                model.registerTap()
            } label: {
                Text("Tap")
                    .font(GKFont.title)
                    .foregroundStyle(GKColor.accent)
                    .frame(width: 96, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GKColor.accent, lineWidth: 2)
                    )
            }
            .accessibilityLabel("Tap tempo")
            .accessibilityHint("Tap in time to set the tempo")

            // +1 BPM.
            stepperButton(symbol: "plus", label: "Increase tempo") {
                model.nudge(by: 1)
            }
        }
    }

    /// A small circular ± stepper button. Factored out so the two share a look.
    private func stepperButton(symbol: String, label: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(GKColor.textPrimary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(GKColor.textSecondary.opacity(0.15)))
        }
        .accessibilityLabel(label)
    }
}

#Preview {
    MetronomeView()
}
