//
//  ScalesView.swift
//  GuitarKit — Scales tool
//
//  The Scales tool screen: pick a root + scale/mode and the notes light up across
//  a horizontal neck (root emphasized), playable ascending/descending, with a
//  handedness mirror, an orientation flip, a note-names/degrees label toggle, and
//  the `Current ⇄ Standard` override. Built on the pure `Fretboard` engine, so
//  the highlighting is correct for any tuning + capo.
//

import SwiftUI

struct ScalesView: View {

    @State private var model = ScalesViewModel()

    var body: some View {
        ZStack {
            GKColor.background.ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Scales")
                    .font(GKFont.largeTitle)
                    .foregroundStyle(GKColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                selectors
                fretboard
                playControls
                toggles
                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Root + scale selectors

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

    // MARK: - The fretboard grid

    private var fretboard: some View {
        // Strings top→bottom and frets left→right, honoring orientation + handedness.
        let strings = stringDisplayOrder()
        let frets = fretDisplayOrder()

        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(strings, id: \.self) { string in
                    HStack(spacing: 6) {
                        ForEach(frets, id: \.self) { fret in
                            cell(string: string, fret: fret)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func cell(string: Int, fret: Int) -> some View {
        let fs = model.fretboardScale
        let inScale = fs.isInScale(string: string, fret: fret)
        let isRoot = fs.isRoot(string: string, fret: fret)

        return ZStack {
            // A faint fret cell background so the grid reads even where empty.
            RoundedRectangle(cornerRadius: 6)
                .fill(GKColor.textSecondary.opacity(fret == 0 ? 0.18 : 0.06))

            if inScale {
                Circle()
                    .fill(isRoot ? GKColor.accent : GKColor.inTune.opacity(0.7))
                    .frame(width: 30, height: 30)
                if let label = model.label(string: string, fret: fret) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 38, height: 34)
        .accessibilityHidden(!inScale)
        .accessibilityLabel(inScale ? (model.label(string: string, fret: fret) ?? "") : "")
    }

    // MARK: - Play controls

    private var playControls: some View {
        HStack(spacing: 16) {
            Button { model.playAscending() } label: {
                Label("Ascending", systemImage: "arrow.up")
            }
            Button { model.playDescending() } label: {
                Label("Descending", systemImage: "arrow.down")
            }
            Button { model.stopPlayback() } label: {
                Image(systemName: "stop.fill")
            }
        }
        .font(GKFont.body)
        .tint(GKColor.accent)
    }

    // MARK: - Toggles

    private var toggles: some View {
        VStack(spacing: 10) {
            Picker("Labels", selection: $model.labelMode) {
                Text("Notes").tag(ScalesViewModel.LabelMode.noteNames)
                Text("Degrees").tag(ScalesViewModel.LabelMode.degrees)
            }
            .pickerStyle(.segmented)

            Toggle("Left-handed", isOn: $model.isLeftHanded)
            Toggle("Flip orientation", isOn: $model.orientationFlipped)
            Toggle("Standard tuning", isOn: $model.useStandardOverride)
        }
        .font(GKFont.body)
        .tint(GKColor.accent)
    }

    // MARK: - Display ordering

    /// String row order (top → bottom). By default the HIGH string is on top (tab
    /// orientation); the orientation flip reverses it.
    private func stringDisplayOrder() -> [Int] {
        let base = Array(0..<model.fretboard.stringCount)   // low → high
        // High on top = reversed; flip toggles that.
        let highOnTop = base.reversed()
        return model.orientationFlipped ? Array(base) : Array(highOnTop)
    }

    /// Fret column order (left → right). Nut on the left by default; left-handed
    /// mirrors so the nut is on the right.
    private func fretDisplayOrder() -> [Int] {
        let base = Array(0...model.fretCount)
        return model.isLeftHanded ? base.reversed() : base
    }

    // MARK: - Names

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
    ScalesView()
}
