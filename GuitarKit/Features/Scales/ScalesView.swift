//
//  ScalesView.swift
//  GuitarKit — Scales tool
//
//  The app is portrait-locked. ScalesView detects the physical device orientation
//  via UIDevice notifications and fake-rotates only its own content 90° when the
//  device is held in landscape. Everything outside (nav bar, other tools) stays
//  portrait-locked as normal.
//
//  Portrait: scrollable fretboard + all three display toggles.
//  Landscape (fake-rotated): full 12-fret diagram that fills the width, play
//  controls + notes/degrees picker. Left-handed / flip / standard-tuning toggles
//  are omitted in landscape.
//
//  System picker popups (.menu style) appear in portrait coordinates and would
//  look rotated in fake-landscape, so landscape uses stepper-style (‹ value ›)
//  selectors that stay entirely within the rotated SwiftUI tree.
//

import SwiftUI
import UIKit

struct ScalesView: View {

    @Bindable var model: ScalesViewModel

    @State private var deviceOrientation: UIDeviceOrientation = .portrait

    private var isLandscape: Bool { deviceOrientation.isLandscape }

    // +90° for landscapeLeft (home button right, device tilted CCW)
    // −90° for landscapeRight (home button left, device tilted CW)
    private var rotationAngle: Double {
        deviceOrientation == .landscapeLeft ? 90 : -90
    }

    // MARK: - UIKit screen metrics

    // The GeometryReader approach is dropped for landscape because .ignoresSafeArea()
    // on the outer reader makes geo.safeAreaInsets return zero. UIKit gives correct
    // values reliably.
    private var windowSafeAreaInsets: UIEdgeInsets {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else { return UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0) }
        return window.safeAreaInsets
    }

    private var screenSize: CGSize {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return CGSize(width: 393, height: 852) }
        return windowScene.screen.bounds.size
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            GKColor.background.ignoresSafeArea()
            if isLandscape {
                landscapeContentView
                    .transition(.opacity)
            } else {
                portraitLayout
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isLandscape)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            refreshOrientation()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            refreshOrientation()
        }
    }

    private func refreshOrientation() {
        let o = UIDevice.current.orientation
        guard o.isLandscape || o.isPortrait else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            deviceOrientation = o
        }
    }

    // MARK: - Landscape rotation wrapper

    private var landscapeContentView: some View {
        let size = screenSize
        let leadingPad: CGFloat  = 85
        let trailingPad: CGFloat = 85

        return landscapeLayout
            .padding(.leading, leadingPad)
            .padding(.trailing, trailingPad)
            .padding(.vertical, 8)
            .frame(width: size.height, height: size.width)
            .rotationEffect(.degrees(rotationAngle))
            .frame(width: size.width, height: size.height)
    }

    // MARK: - Portrait layout (unchanged)

    private var portraitLayout: some View {
        VStack(spacing: 18) {
            Text("Scales")
                .font(GKFont.largeTitle)
                .foregroundStyle(GKColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            selectors
            portraitFretboard
            playControls
            portraitToggles
        }
        .padding()
        .padding(.bottom, 96)
    }

    // MARK: - Landscape layout

    private var landscapeLayout: some View {
        VStack(spacing: 10) {
            Text("Scales")
                .font(GKFont.title)
                .foregroundStyle(GKColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            landscapeSelectors
            landscapeFretboard
            landscapeBottomBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Portrait selectors (Picker popups — portrait only)

    private var selectors: some View {
        HStack(spacing: 12) {
            Picker("Root", selection: $model.root) {
                ForEach(PitchClass.allCases, id: \.self) { pc in
                    Text(pc.name).tag(pc)
                }
            }
            Picker("Scale", selection: $model.scaleType) {
                ForEach(ScaleType.allCases, id: \.self) { type in
                    Text(scaleName(type)).tag(type)
                }
            }
        }
        .pickerStyle(.menu)
        .tint(GKColor.accent)
    }

    // MARK: - Landscape selectors (inline stepper — no system popups)

    // System popups render in portrait coordinates and appear sideways in
    // fake-landscape, so landscape uses ‹ value › buttons that stay within the
    // rotated SwiftUI layer.
    private var landscapeSelectors: some View {
        HStack(spacing: 16) {
            stepperControl(
                label: model.root.name,
                minWidth: 28,
                prev: { model.root = cycled(PitchClass.allCases, before: model.root) },
                next: { model.root = cycled(PitchClass.allCases, after: model.root) }
            )
            stepperControl(
                label: scaleName(model.scaleType),
                minWidth: 120,
                prev: { model.scaleType = cycled(ScaleType.allCases, before: model.scaleType) },
                next: { model.scaleType = cycled(ScaleType.allCases, after: model.scaleType) }
            )
        }
    }

    private func stepperControl(label: String, minWidth: CGFloat,
                                prev: @escaping () -> Void,
                                next: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: prev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GKColor.accent)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Text(label)
                .font(GKFont.body)
                .foregroundStyle(GKColor.textPrimary)
                .lineLimit(1)
                .frame(minWidth: minWidth, alignment: .center)

            Button(action: next) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GKColor.accent)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GKColor.textSecondary.opacity(0.1))
        )
    }

    // MARK: - Fretboard (portrait — horizontal scroll)

    private var portraitFretboard: some View {
        let strings = stringRows(flipped: model.orientationFlipped)
        let frets   = fretColumns(leftHanded: model.isLeftHanded)
        let fs      = model.fretboardScale

        return ScrollView(.horizontal, showsIndicators: false) {
            fretGrid(strings: strings, frets: frets, fs: fs, cellW: 38, cellH: 34)
                .padding(.vertical, 8)
                .padding(model.isLeftHanded ? .trailing : .leading, 12)
                .overlay(alignment: model.isLeftHanded ? .trailing : .leading) {
                    nutBar
                }
        }
    }

    // MARK: - Fretboard (landscape — fills width, no scroll)

    private var landscapeFretboard: some View {
        let strings = stringRows(flipped: false)
        let frets   = fretColumns(leftHanded: false)
        let fs      = model.fretboardScale

        return GeometryReader { geo in
            let gap: CGFloat = 4
            let nutPad: CGFloat = 10
            let cellW = (geo.size.width - nutPad - gap * CGFloat(frets.count - 1)) / CGFloat(frets.count)
            let cellH: CGFloat = max(24, (geo.size.height - 22 - gap * CGFloat(strings.count - 1)) / CGFloat(strings.count + 1))

            fretGrid(strings: strings, frets: frets, fs: fs, cellW: cellW, cellH: cellH)
                .padding(.leading, nutPad)
                .overlay(alignment: .leading) { nutBar }
        }
    }

    // MARK: - Shared grid

    private func fretGrid(strings: [Int], frets: [Int], fs: FretboardScale,
                          cellW: CGFloat, cellH: CGFloat) -> some View {
        let gap: CGFloat = 4
        return VStack(spacing: gap) {
            ForEach(strings, id: \.self) { string in
                HStack(spacing: gap) {
                    ForEach(frets, id: \.self) { fret in
                        cell(string: string, fret: fret, fs: fs, w: cellW, h: cellH)
                    }
                }
            }
            HStack(spacing: gap) {
                ForEach(frets, id: \.self) { fret in
                    Text("\(fret)")
                        .font(.system(size: min(11, cellW * 0.45),
                                      weight: fret == 0 ? .bold : .regular,
                                      design: .rounded))
                        .foregroundStyle(fret == 0 ? GKColor.accent : GKColor.textSecondary)
                        .frame(width: cellW)
                }
            }
        }
    }

    private var nutBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(GKColor.textPrimary.opacity(0.65))
            .frame(width: 5)
            .padding(.vertical, 6)
            .accessibilityHidden(true)
    }

    private func cell(string: Int, fret: Int, fs: FretboardScale,
                      w: CGFloat, h: CGFloat) -> some View {
        let inScale = fs.isInScale(string: string, fret: fret)
        let isRoot  = fs.isRoot(string: string, fret: fret)
        let label   = inScale ? model.label(string: string, fret: fret, in: fs) : nil
        let dot     = min(w, h) * 0.8

        return ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(GKColor.textSecondary.opacity(fret == 0 ? 0.18 : 0.06))
            if inScale {
                Circle()
                    .fill(isRoot ? GKColor.accent : GKColor.inTune.opacity(0.7))
                    .frame(width: dot, height: dot)
                if let label {
                    Text(label)
                        .font(.system(size: max(7, dot * 0.38),
                                      weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: w, height: h)
        .accessibilityHidden(!inScale)
        .accessibilityLabel(label ?? "")
    }

    // MARK: - Play controls (shared)

    private var playControls: some View {
        HStack(spacing: 16) {
            Button { model.playAscending()  } label: { Label("Ascending",  systemImage: "arrow.up")   }
            Button { model.playDescending() } label: { Label("Descending", systemImage: "arrow.down") }
            Button { model.stopPlayback()   } label: { Image(systemName: "stop.fill") }
        }
        .font(GKFont.body)
        .tint(GKColor.accent)
    }

    // MARK: - Landscape bottom bar (play + notes/degrees)

    private var landscapeBottomBar: some View {
        HStack {
            playControls
            Spacer()
            GKSegmentedPicker(
                options: [(.noteNames, "Notes"), (.degrees, "Degrees")],
                selection: $model.labelMode
            )
            .frame(width: 150)
        }
    }

    // MARK: - Portrait toggles

    private var portraitToggles: some View {
        VStack(spacing: 10) {
            GKSegmentedPicker(
                options: [(.noteNames, "Notes"), (.degrees, "Degrees")],
                selection: $model.labelMode
            )
            Toggle("Left-handed",      isOn: $model.isLeftHanded)
            Toggle("Flip orientation", isOn: $model.orientationFlipped)
            Toggle("Standard tuning",  isOn: $model.useStandardOverride)
        }
        .font(GKFont.body)
        .toggleStyle(GKToggleStyle())
    }

    // MARK: - Cyclic value helpers

    private func cycled<T: Equatable>(_ all: [T], after current: T) -> T {
        guard let idx = all.firstIndex(of: current) else { return current }
        return all[(idx + 1) % all.count]
    }

    private func cycled<T: Equatable>(_ all: [T], before current: T) -> T {
        guard let idx = all.firstIndex(of: current) else { return current }
        return all[(idx - 1 + all.count) % all.count]
    }

    // MARK: - Display ordering

    private func stringRows(flipped: Bool) -> [Int] {
        let base = Array(0..<model.fretboard.stringCount)
        return flipped ? base : base.reversed()
    }

    private func fretColumns(leftHanded: Bool) -> [Int] {
        let base = Array(0...model.fretCount)
        return leftHanded ? base.reversed() : base
    }

    // MARK: - Scale names

    private func scaleName(_ type: ScaleType) -> String {
        switch type {
        case .major:            return "Major"
        case .naturalMinor:     return "Natural Minor"
        case .harmonicMinor:    return "Harmonic Minor"
        case .melodicMinor:     return "Melodic Minor"
        case .majorPentatonic:  return "Major Pentatonic"
        case .minorPentatonic:  return "Minor Pentatonic"
        case .blues:            return "Blues"
        case .ionian:           return "Ionian"
        case .dorian:           return "Dorian"
        case .phrygian:         return "Phrygian"
        case .lydian:           return "Lydian"
        case .mixolydian:       return "Mixolydian"
        case .aeolian:          return "Aeolian"
        case .locrian:          return "Locrian"
        }
    }
}

#Preview {
    ScalesView(model: ScalesViewModel())
}
