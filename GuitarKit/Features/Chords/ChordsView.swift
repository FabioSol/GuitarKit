//
//  ChordsView.swift
//  GuitarKit — Chords tool
//
//  The Chords tool screen: pick a root + quality and see a PLAYABLE voicing drawn
//  as a vertical chord box (strings as vertical lines, frets as horizontal lines,
//  dots on the fingered positions, O/X markers above open/muted strings). Cycle
//  through alternate shapes up the neck, and play the chord as a block or a strum.
//  Built on the pure `Fretboard` + voicing engines, so the shape is correct for
//  any tuning + capo, with a curated open-chord library as a fallback in standard
//  tuning.
//
//  This is the sibling of `ScalesView` and mirrors its house style: a
//  `ZStack + GKColor.background` layout, menu pickers tinted with the accent, the
//  same handedness mirror, label-mode toggle, and `Current ⇄ Standard` override.
//

import SwiftUI

struct ChordsView: View {

    @State private var model = ChordsViewModel()

    var body: some View {
        ZStack {
            GKColor.background.ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Chords")
                    .font(GKFont.largeTitle)
                    .foregroundStyle(GKColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                selectors
                chordName
                chordBox
                voicingControls
                playControls
                toggles
                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Root + quality selectors

    private var selectors: some View {
        HStack(spacing: 12) {
            Picker("Root", selection: $model.root) {
                ForEach(PitchClass.allCases, id: \.self) { pc in
                    Text(pc.name).tag(pc)
                }
            }
            Picker("Quality", selection: $model.quality) {
                ForEach(ChordQuality.allCases, id: \.self) { quality in
                    Text(qualityName(quality)).tag(quality)
                }
            }
        }
        .pickerStyle(.menu)
        .tint(GKColor.accent)
        // Changing the chord should drop us back on the default (lowest) shape,
        // not leave us mid-cycle on a stale index.
        .onChange(of: model.root) { _, _ in model.resetVoicing() }
        .onChange(of: model.quality) { _, _ in model.resetVoicing() }
    }

    /// The chord's full name ("C", "Am7", "G7") shown big above the box, with the
    /// "voicing N of M" counter so the cycle button's effect is visible.
    private var chordName: some View {
        VStack(spacing: 2) {
            Text("\(model.root.name)\(model.quality.symbol)")
                .font(GKFont.title)
                .foregroundStyle(GKColor.textPrimary)
            if model.voicingCount > 1 {
                Text("Voicing \(model.voicingIndex + 1) of \(model.voicingCount)")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
            }
        }
    }

    // MARK: - The vertical chord box

    /// The chord diagram. Strings run TOP→BOTTOM as vertical lines and frets run
    /// LEFT→RIGHT as horizontal lines — the standard vertical chord-box the spec
    /// asks us to default to. Handedness mirrors the string columns.
    private var chordBox: some View {
        // String columns left→right. By convention the LOW string is on the left
        // (like looking at the neck head-on, low E nearest you on the left); the
        // left-handed toggle mirrors that so the low string moves to the right.
        let strings = stringDisplayOrder()
        // Fret rows top→bottom: row 0 is the nut/open area, then frets 1…fretCount.
        let fretRows = Array(0...model.fretCount)

        return VStack(spacing: 4) {
            // Top row: O (open) / X (muted) markers above each string column.
            HStack(spacing: 0) {
                ForEach(strings, id: \.self) { string in
                    Text(openMutedMarker(forString: string))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(GKColor.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // The grid of fret cells. Each row is one fret; each column one string.
            VStack(spacing: 0) {
                ForEach(fretRows, id: \.self) { fret in
                    HStack(spacing: 0) {
                        ForEach(strings, id: \.self) { string in
                            cell(string: string, fret: fret)
                        }
                    }
                }
            }
            .background(
                // A faint rounded backdrop so the grid reads as a fretboard panel.
                RoundedRectangle(cornerRadius: 8)
                    .fill(GKColor.textSecondary.opacity(0.06))
            )
            .overlay(
                // A thicker bar along the very top = the NUT, but only when this is
                // an open-position shape (nothing fingered above fret 0). For shapes
                // up the neck there's no nut on screen, so we hide it.
                nutBar, alignment: .top
            )
        }
        .frame(height: 240)
        .padding(.horizontal, 24)
    }

    /// One cell of the grid: draws the string line + fret line, and a filled dot
    /// when the current voicing frets THIS string at THIS fret.
    private func cell(string: Int, fret: Int) -> some View {
        let voicing = model.currentVoicing
        let frettedHere = voicing.frets.indices.contains(string)
            && voicing.frets[string] == fret
            && fret > 0   // fret 0 is "open", shown by the O marker, not a dot

        return ZStack {
            // The vertical string line runs down the middle of every cell.
            Rectangle()
                .fill(GKColor.textSecondary.opacity(0.5))
                .frame(width: 1.5)

            // The horizontal fret line sits at the TOP of each cell (so the line
            // between fret 0 and fret 1 reads as the first fret wire, etc.). We
            // skip it on the very first row so the nut overlay owns that edge.
            VStack {
                if fret > 0 {
                    Rectangle()
                        .fill(GKColor.textSecondary.opacity(0.35))
                        .frame(height: 1)
                }
                Spacer()
            }

            // The finger dot.
            if frettedHere {
                Circle()
                    .fill(isRoot(string: string, fret: fret) ? GKColor.accent
                                                              : GKColor.inTune.opacity(0.85))
                    .frame(width: 26, height: 26)
                if let label = model.label(forString: string) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
    }

    /// The nut bar: a thick line at the top edge, shown only for open-position
    /// shapes (no fingered note sits above fret 0 in this voicing).
    @ViewBuilder
    private var nutBar: some View {
        if isOpenPosition {
            Rectangle()
                .fill(GKColor.textPrimary.opacity(0.6))
                .frame(height: 3)
        }
    }

    // MARK: - Voicing cycle control

    private var voicingControls: some View {
        Button {
            model.cycleVoicing()
        } label: {
            Label("Next voicing", systemImage: "arrow.triangle.2.circlepath")
        }
        .font(GKFont.body)
        .tint(GKColor.accent)
        // Nothing to cycle to when there's only one shape — dim the button.
        .disabled(model.voicingCount <= 1)
    }

    // MARK: - Play controls

    private var playControls: some View {
        HStack(spacing: 16) {
            Button { model.playBlock() } label: {
                Label("Block", systemImage: "square.stack.3d.up.fill")
            }
            Button { model.playStrum() } label: {
                Label("Strum", systemImage: "hand.draw.fill")
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
                Text("Notes").tag(ChordsViewModel.LabelMode.noteNames)
                Text("Degrees").tag(ChordsViewModel.LabelMode.degrees)
            }
            .pickerStyle(.segmented)

            Toggle("Left-handed", isOn: $model.isLeftHanded)
            Toggle("Standard tuning", isOn: $model.useStandardOverride)
        }
        .font(GKFont.body)
        .tint(GKColor.accent)
    }

    // MARK: - Diagram helpers

    /// Whether the current voicing is an OPEN-position shape: nothing is fingered
    /// above fret 0. Drives whether we draw the nut bar.
    private var isOpenPosition: Bool {
        // `lowestFrettedFret == nil` means a pure open/muted chord; otherwise it's
        // open position only when the lowest fingered fret is 1 (right at the nut).
        guard let lowest = model.currentVoicing.lowestFrettedFret else { return true }
        return lowest <= 1
    }

    /// The "O" / "X" / " " marker to show above a string column: "O" if it's played
    /// open (fret 0), "X" if muted, blank if it's fingered (the dot speaks for it).
    private func openMutedMarker(forString string: Int) -> String {
        let frets = model.currentVoicing.frets
        guard frets.indices.contains(string) else { return " " }
        switch frets[string] {
        case .none:   return "✕"   // muted
        case .some(0): return "○"  // open
        default:       return " "  // fingered → no marker, the dot shows it
        }
    }

    /// Whether the note at (string, fret) in the current voicing is the chord ROOT
    /// — used to color the root dot with the accent so it stands out, exactly like
    /// the Scales tool emphasizes its root.
    private func isRoot(string: Int, fret: Int) -> Bool {
        guard let note = model.fretboard.note(string: string, fret: fret) else { return false }
        return note.pitchClass == model.root
    }

    /// String column order (left → right). Low string on the left by default; the
    /// left-handed toggle mirrors the columns so the low string moves to the right.
    private func stringDisplayOrder() -> [Int] {
        let base = Array(0..<model.fretboard.stringCount)   // low → high
        return model.isLeftHanded ? base.reversed() : base
    }

    // MARK: - Names

    /// A readable label for a chord quality in the picker (the bare `.symbol` is
    /// terse — "" for major — so we spell the common ones out for clarity).
    private func qualityName(_ quality: ChordQuality) -> String {
        switch quality {
        case .major:                    return "Major"
        case .minor:                    return "Minor"
        case .diminished:               return "Diminished"
        case .augmented:                return "Augmented"
        case .sus2:                     return "Sus2"
        case .sus4:                     return "Sus4"
        case .add9:                     return "Add9"
        case .sixth:                    return "6"
        case .minorSixth:               return "Minor 6"
        case .sixNine:                  return "6/9"
        case .dominantSeventh:          return "Dominant 7"
        case .majorSeventh:             return "Major 7"
        case .minorSeventh:             return "Minor 7"
        case .minorMajorSeventh:        return "Minor/Major 7"
        case .halfDiminished:           return "Half-Diminished (m7♭5)"
        case .diminishedSeventh:        return "Diminished 7"
        case .augmentedSeventh:         return "Augmented 7"
        case .dominantNinth:            return "Dominant 9"
        case .dominantEleventh:         return "Dominant 11"
        case .dominantThirteenth:       return "Dominant 13"
        case .majorNinth:               return "Major 9"
        case .minorNinth:               return "Minor 9"
        case .dominantSeventhFlatNine:  return "7♭9"
        case .dominantSeventhSharpNine: return "7♯9"
        }
    }
}

#Preview {
    ChordsView()
}
