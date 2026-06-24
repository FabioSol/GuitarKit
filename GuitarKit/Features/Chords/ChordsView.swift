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

    /// The Chords state. INJECTED by `RootView` (which owns it via `@State`) so
    /// the tool's selection survives navigation, and so the Circle-of-Fifths
    /// diatonic-chord chips can load a chord into it before we appear (slice #21).
    /// `@Bindable` gives the two-way `$model.…` bindings the pickers/toggles need.
    @Bindable var model: ChordsViewModel

    var body: some View {
        ZStack {
            GKColor.background.ignoresSafeArea()

            // A ScrollView so the tall chord box + all the controls fit on small
            // iPhones (and matches the Metronome / Circle tools). The content
            // scrolls under the floating nav; the bottom padding keeps the last
            // control clear of it.
            ScrollView {
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
                }
                .padding()
                // Reserve room at the bottom so the toggles clear the floating
                // rotary nav.
                .padding(.bottom, 96)
            }
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

    /// Width of one string column. Fixed (not stretched to fill the screen) so the
    /// whole box stays PORTRAIT — taller than wide, like a real chord chart — and
    /// the vertical string lines read as the long dimension of the neck.
    private let cellWidth: CGFloat = 34
    /// Height of one fret row. Taller than `cellWidth` so each cell is portrait.
    private let cellHeight: CGFloat = 42

    /// The chord diagram. Strings run TOP→BOTTOM as thin vertical lines and frets
    /// run LEFT→RIGHT as horizontal lines, with a thick NUT at the top — the
    /// standard vertical chord box. Sized portrait and CENTERED. Handedness
    /// mirrors the string columns.
    private var chordBox: some View {
        // String columns left→right. By convention the LOW string is on the left
        // (like looking at the neck head-on, low E nearest you on the left); the
        // left-handed toggle mirrors that so the low string moves to the right.
        let strings = stringDisplayOrder()
        // Fret rows top→bottom: row 0 is the nut/open area, then frets 1…fretCount.
        let fretRows = Array(0...model.fretCount)
        // Resolve the voicing + board ONCE per render and hand them to every cell
        // / marker, instead of each cell re-running the generator + library.
        let voicing = model.currentVoicing
        let board = model.fretboard

        return VStack(spacing: 4) {
            // Top row: O (open) / X (muted) markers above each string column.
            HStack(spacing: 0) {
                ForEach(strings, id: \.self) { string in
                    Text(openMutedMarker(forString: string, voicing: voicing))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(GKColor.textSecondary)
                        .frame(width: cellWidth)
                }
            }

            // The grid of fret cells. Each row is one fret; each column one string.
            VStack(spacing: 0) {
                ForEach(fretRows, id: \.self) { fret in
                    HStack(spacing: 0) {
                        ForEach(strings, id: \.self) { string in
                            cell(string: string, fret: fret, voicing: voicing, board: board)
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
                nutBar(voicing: voicing), alignment: .top
            )
        }
        // A fixed-size, centered portrait box (not stretched across the screen).
        .frame(maxWidth: .infinity)
        // The chord box is a visual grid of dots; collapse it into ONE VoiceOver
        // element that speaks the whole voicing (slice #23), since cell-by-cell
        // navigation of a diagram reads poorly. Updates as the voicing changes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.voicingAccessibilityDescription)
    }

    /// One cell of the grid: draws the string line + fret line, and a filled dot
    /// when the current voicing frets THIS string at THIS fret.
    private func cell(string: Int, fret: Int, voicing: ChordVoicing, board: Fretboard) -> some View {
        let frettedHere = voicing.frets.indices.contains(string)
            && voicing.frets[string] == fret
            && fret > 0   // fret 0 is "open", shown by the O marker, not a dot

        return ZStack {
            // The vertical string line runs down the middle of every cell. Kept
            // THIN (and lighter than the fret wires) so it never gets mistaken for
            // a fret — the user's confusion was thick strings reading as frets.
            Rectangle()
                .fill(GKColor.textSecondary.opacity(0.35))
                .frame(width: 1)

            // The horizontal fret WIRE sits at the TOP of each cell (so the line
            // between fret 0 and fret 1 reads as the first fret wire, etc.). A
            // touch heavier than the strings so the grid reads as "frets across,
            // strings down." We skip it on the first row so the nut overlay owns
            // that edge.
            VStack {
                if fret > 0 {
                    Rectangle()
                        .fill(GKColor.textSecondary.opacity(0.5))
                        .frame(height: 1.5)
                }
                Spacer()
            }

            // The finger dot.
            if frettedHere {
                Circle()
                    .fill(isRoot(string: string, fret: fret, board: board) ? GKColor.accent
                                                              : GKColor.inTune.opacity(0.85))
                    .frame(width: 26, height: 26)
                if let label = model.label(forString: string, in: voicing, board: board) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: cellWidth, height: cellHeight)
    }

    /// The nut bar: a thick line at the top edge, shown only for open-position
    /// shapes (no fingered note sits above fret 0 in this voicing).
    @ViewBuilder
    private func nutBar(voicing: ChordVoicing) -> some View {
        if isOpenPosition(voicing) {
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
    private func isOpenPosition(_ voicing: ChordVoicing) -> Bool {
        // `lowestFrettedFret == nil` means a pure open/muted chord; otherwise it's
        // open position only when the lowest fingered fret is 1 (right at the nut).
        guard let lowest = voicing.lowestFrettedFret else { return true }
        return lowest <= 1
    }

    /// The "O" / "X" / " " marker to show above a string column: "O" if it's played
    /// open (fret 0), "X" if muted, blank if it's fingered (the dot speaks for it).
    private func openMutedMarker(forString string: Int, voicing: ChordVoicing) -> String {
        let frets = voicing.frets
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
    private func isRoot(string: Int, fret: Int, board: Fretboard) -> Bool {
        guard let note = board.note(string: string, fret: fret) else { return false }
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
    ChordsView(model: ChordsViewModel())
}
