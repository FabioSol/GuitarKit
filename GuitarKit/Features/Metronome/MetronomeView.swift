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

    /// The view model. INJECTED by `RootView` (which owns it via `@State`) so the
    /// tempo / time signature / accents survive navigating away and back, like the
    /// other tools. `@Bindable` for two-way bindings; audio still stops on leave
    /// via `.onDisappear`.
    @Bindable var model: MetronomeViewModel

    /// Global preferences, supplied by the app shell. The metronome's SOUND SET
    /// and PER-BEAT HAPTIC live in Settings (off the face), so we read them here
    /// and push them into the model. Optional so previews work without a store.
    @Environment(SettingsStore.self) private var settings: SettingsStore?

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

            VStack(spacing: 24) {
                Text("Metronome")
                    .font(GKFont.largeTitle)
                    .foregroundStyle(GKColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                dial
                transportButton
                tapAndSteppers

                // The musical configuration added in slice #16.
                configControls
            }
            .padding()
            .padding(.bottom, 96)
        }
        // Sync the sound set + per-beat haptic from Settings (their home now),
        // on appear and whenever the user changes them in Settings.
        .onAppear { applyMetronomeSettings() }
        .onChange(of: settings?.metronomeSoundSet) { _, _ in applyMetronomeSettings() }
        .onChange(of: settings?.metronomeHapticsEnabled) { _, _ in applyMetronomeSettings() }
    }

    /// Copy the Settings-owned sound set + haptic into the model (which pushes
    /// them to the engine, restarting if it's playing). No-op without a store.
    private func applyMetronomeSettings() {
        guard let settings else { return }
        model.setSoundSet(settings.metronomeSoundSet)
        model.setHapticsEnabled(settings.metronomeHapticsEnabled)
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

    /// The ring of beat dots — now redrawn to the time signature's beat count and
    /// TAPPABLE. Each dot shows its accent state (accent = filled + larger,
    /// normal = outline, muted = hollow with an ×). Tapping a dot cycles it
    /// accent → normal → muted. The currently-playing beat also glows.
    ///
    /// NOTE: the ring sits ON TOP of the dial's drag gesture, so we attach a tap
    /// gesture to each dot. To keep the dots easy to hit (and not fight the
    /// drag), each dot has a larger transparent hit area via `contentShape`.
    private var beatRing: some View {
        // The radius at which dots sit: just inside the stroked ring.
        let radius = dialSize / 2 - 6

        return ZStack {
            ForEach(0..<model.beatsPerBar, id: \.self) { beat in
                let accent = model.beatAccents.indices.contains(beat)
                    ? model.beatAccents[beat] : .normal
                let isActive = beat == model.currentBeat && model.isPlaying

                beatDot(accent: accent, isActive: isActive)
                    // Place the dot using trig (top = 12 o'clock, clockwise).
                    .offset(dotOffset(beat: beat, radius: radius))
                    // A subtle pop when a beat lights up.
                    .animation(.easeOut(duration: 0.12), value: model.currentBeat)
                    // Tap to cycle this beat's accent state.
                    .onTapGesture { model.cycleAccent(at: beat) }
                    .accessibilityLabel("Beat \(beat + 1)")
                    .accessibilityValue(accent.displayHint)
                    .accessibilityHint("Tap to change emphasis")
            }
        }
    }

    /// One beat-ring dot, drawn to clearly distinguish its accent state:
    ///   • accent → a larger, filled accent-colored disc
    ///   • normal → a medium hollow ring (outline only)
    ///   • muted  → a dim hollow ring with a small × through it
    /// When that beat is the one currently sounding, it brightens.
    @ViewBuilder
    private func beatDot(accent: BeatAccent, isActive: Bool) -> some View {
        // A generous transparent hit target so the dots are easy to tap without
        // requiring pixel precision over the small visible shape.
        let hitSize: CGFloat = 32

        // The color the dot glows when it's the beat currently sounding.
        let glow: Color = {
            switch accent {
            case .accent: return GKColor.accent
            case .normal: return GKColor.inTune
            case .muted:  return GKColor.textSecondary
            }
        }()

        ZStack {
            switch accent {
            case .accent:
                Circle()
                    .fill(isActive ? GKColor.accent : GKColor.accent.opacity(0.85))
                    .frame(width: 18, height: 18)
            case .normal:
                // Filled when sounding (a clear bright pulse), hollow otherwise.
                Circle()
                    .fill(isActive ? GKColor.inTune : Color.clear)
                    .overlay(
                        Circle().stroke(isActive ? GKColor.inTune
                                                 : GKColor.textSecondary.opacity(0.7),
                                        lineWidth: 2.5)
                    )
                    .frame(width: 14, height: 14)
            case .muted:
                // A dim hollow ring with an × — clearly "this one is silent."
                ZStack {
                    Circle()
                        .stroke(GKColor.textSecondary.opacity(isActive ? 0.7 : 0.35),
                                lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(GKColor.textSecondary.opacity(isActive ? 0.8 : 0.45))
                }
            }
        }
        // Make the SOUNDING beat unmistakable: pop it larger and wrap it in a
        // colored halo. The `.animation` on the ring (keyed to currentBeat)
        // makes this a quick pulse as the beat moves around.
        .scaleEffect(isActive ? 1.5 : 1.0)
        .shadow(color: glow.opacity(isActive ? 0.9 : 0), radius: isActive ? 7 : 0)
        // Expand the tappable area to `hitSize` while keeping the drawn shape
        // small. `contentShape` makes the whole (transparent) frame hit-testable.
        .frame(width: hitSize, height: hitSize)
        .contentShape(Circle())
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

    /// A circular ± stepper button. `size` lets callers use a compact version
    /// (the time-signature row) vs the larger tap-tempo steppers.
    private func stepperButton(symbol: String, label: String,
                               size: CGFloat = 48,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(GKColor.textPrimary)
                .frame(width: size, height: size)
                .background(Circle().fill(GKColor.textSecondary.opacity(0.15)))
        }
        .accessibilityLabel(label)
    }

    // MARK: - Configuration controls (slice #16)
    //
    // The musical setup below the transport: time signature (presets + a custom
    // beat-count stepper) and subdivision. The sound set and the per-beat haptic
    // live in Settings (kept off the face to reduce on-screen clutter); this view
    // syncs them from the store — see `applyMetronomeSettings()`.

    /// All the configuration rows, stacked.
    private var configControls: some View {
        VStack(spacing: 18) {
            timeSignatureRow
            subdivisionRow
        }
        .padding(.top, 8)
    }

    /// Time-signature presets as a menu, plus a ± stepper for a CUSTOM beat
    /// count. We show the current signature's label so it's always clear.
    private var timeSignatureRow: some View {
        configRow(title: "Time signature") {
            HStack(spacing: 12) {
                // Preset picker as a pull-down menu.
                Menu {
                    ForEach(TimeSignature.presets, id: \.self) { sig in
                        Button(sig.label) { model.setTimeSignature(sig) }
                    }
                } label: {
                    pillLabel(model.timeSignature.label)
                }
                .accessibilityLabel("Time signature presets")

                // Custom beat-count stepper: change just the number of beats.
                // Compact (34pt) steppers keep this row short.
                HStack(spacing: 2) {
                    stepperButton(symbol: "minus", label: "Fewer beats", size: 34) {
                        model.setCustomBeats(model.beatsPerBar - 1)
                    }
                    Text("\(model.beatsPerBar) beats")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                        .frame(minWidth: 56)
                    stepperButton(symbol: "plus", label: "More beats", size: 34) {
                        model.setCustomBeats(model.beatsPerBar + 1)
                    }
                }
            }
        }
    }

    /// Subdivision picker (quarter / eighth / triplet / sixteenth) as a segmented
    /// row of selectable pills.
    private var subdivisionRow: some View {
        configRow(title: "Subdivision") {
            HStack(spacing: 8) {
                ForEach(Subdivision.allCases, id: \.self) { sub in
                    selectablePill(sub.label, isSelected: model.subdivision == sub) {
                        model.setSubdivision(sub)
                    }
                }
            }
        }
    }

    // MARK: - Small reusable control bits

    /// A labeled configuration row: a title on the left, the control on the
    /// right. Keeps every row visually consistent.
    private func configRow<Content: View>(title: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(GKFont.body)
                .foregroundStyle(GKColor.textPrimary)
            Spacer()
            content()
        }
    }

    /// A static "pill" label (used for the time-signature menu trigger). Kept
    /// short (low vertical padding) so it doesn't tower over the row.
    private func pillLabel(_ text: String) -> some View {
        Text(text)
            .font(GKFont.caption.weight(.semibold))
            .foregroundStyle(GKColor.accent)
            // Keep the signature on ONE line — without this the HStack squeezes
            // the menu label and "4/4" wraps onto two lines.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(GKColor.accent, lineWidth: 1.5)
            )
    }

    /// A tappable pill that shows selected/unselected state — selected fills with
    /// the accent, unselected is a faint outline. Used by the subdivision and
    /// sound-set rows.
    private func selectablePill(_ text: String, isSelected: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(GKFont.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : GKColor.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? GKColor.accent : Color.clear)
                )
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(GKColor.textSecondary.opacity(isSelected ? 0 : 0.4),
                                lineWidth: 1)
                )
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    MetronomeView(model: MetronomeViewModel())
}
