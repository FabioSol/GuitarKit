//
//  KeyDetailsPanelView.swift
//  GuitarKit — Circle of Fifths feature
//
//  The details panel that sits BELOW the wheel (PRD: "all hub actions live in the
//  details panel," spatially separated from the selector wheel). For the selected
//  key it shows three things story 44 asks for:
//    1. the key signature (how many sharps/flats, and which notes),
//    2. the relative minor (or relative major, for a minor selection), and
//    3. the seven diatonic chords as chips (Roman numeral + chord symbol).
//
//  In this slice the chord chips are display-only. Later (slice #21) they become
//  cross-links that jump to the Chords tool; for now tapping one calls the view
//  model's no-op `onPlayChord` hook (reserved for slice #13's synth).
//

import SwiftUI

struct KeyDetailsPanelView: View {

    /// The shared view model, read for the selected key and its derived details.
    let viewModel: CircleOfFifthsViewModel

    /// CROSS-LINKS (slice #21): open a diatonic chord in the Chords tool, or the
    /// selected key's scale in the Scales tool. Supplied by the shell; default
    /// no-ops keep the panel previewable in isolation.
    var onOpenChord: (Chord) -> Void = { _ in }
    var onOpenScale: (Scale) -> Void = { _ in }

    var body: some View {
        // A vertical stack of titled sections, left-aligned.
        VStack(alignment: .leading, spacing: 16) {

            // The selected key's name as the heading, with a DISCRETE "View
            // scale" chip tucked on the trailing side (rather than a big full-width
            // button) so the panel stays compact.
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.selectedKey.name)
                    .font(GKFont.title)
                    .foregroundStyle(GKColor.textPrimary)
                Spacer()
                viewScaleButton
            }

            signatureRow
            relativeRow
            diatonicChordsSection
        }
        .padding(20)
        // Wrap the whole panel in our Liquid Glass chrome surface. The panel is
        // "functional chrome," not hero content, so glass is appropriate here, and
        // `gkGlass` handles the opaque fallback under Reduce Transparency for us.
        .gkGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Group the panel for VoiceOver but still let the chord chips inside be
        // individually focusable (`.contain` keeps children separately
        // accessible, unlike `.combine` which would merge them into one element).
        .accessibilityElement(children: .contain)
    }

    // MARK: - Key signature

    /// "Key signature: 2 sharps (F♯, C♯)" — or "no sharps or flats" for C major.
    private var signatureRow: some View {
        // Pull the data from the already-tested harmony domain.
        let key = viewModel.selectedKey
        let count = abs(key.sharpsOrFlats)
        let isSharp = key.sharpsOrFlats > 0
        // The spelled accidental notes (e.g. F♯, C♯), joined for display.
        let noteNames = key.keySignature.map(\.name).joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Key signature")

            if count == 0 {
                Text("No sharps or flats")
                    .font(GKFont.body)
                    .foregroundStyle(GKColor.textPrimary)
            } else {
                // Singular/plural ("1 sharp" vs "2 sharps") read naturally.
                let word = isSharp ? "sharp" : "flat"
                let plural = count == 1 ? word : word + "s"
                Text("\(count) \(plural) — \(noteNames)")
                    .font(GKFont.body)
                    .foregroundStyle(GKColor.textPrimary)
            }
        }
    }

    // MARK: - Relative key

    /// "Relative minor: A minor" (or "Relative major: …" when a minor key is
    /// selected, so the label is always truthful).
    private var relativeRow: some View {
        let relative = viewModel.relativeKey
        // Whichever mode the *relative* key is, name the relationship correctly.
        let label = relative.mode == .minor ? "Relative minor" : "Relative major"

        return VStack(alignment: .leading, spacing: 4) {
            sectionTitle(label)
            Text(relative.name)
                .font(GKFont.body)
                .foregroundStyle(GKColor.textPrimary)
        }
    }

    // MARK: - Diatonic chords

    /// The seven diatonic chord chips, wrapped so they flow onto multiple lines
    /// on narrow screens.
    private var diatonicChordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Diatonic chords")

            // `WrapHStack`-style flow via SwiftUI's `Layout`-free approach: a
            // simple wrapping with `FlowLayout` would need iOS 16+ Layout; to keep
            // this slice dependency-free we use a fixed two-row arrangement of the
            // seven chords inside a horizontally scrolling stack, which always
            // fits and stays simple.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // `id: \.degree` gives each chip a stable identity for ForEach
                    // (degree 1…7 is unique within a key).
                    ForEach(viewModel.diatonicChords, id: \.degree) { diatonic in
                        chordChip(diatonic)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// One diatonic chord chip: the Roman numeral on top, the concrete chord
    /// symbol (e.g. "Dm") below.
    private func chordChip(_ diatonic: DiatonicChord) -> some View {
        // Build a readable chord symbol from the root pitch class + quality.
        // NOTE: the root is a `PitchClass`, which only knows sharp spelling, so
        // a chip may read "A♯m" where strict key spelling would prefer "B♭m".
        // That's a known limitation of the current Chord representation (flagged
        // in Chord.swift) and is purely cosmetic — the chord's *notes* are right.
        let symbol = diatonic.chord.root.name + diatonic.chord.quality.symbol

        return Button {
            // CROSS-LINK (slice #21): open this chord in the Chords tool, loaded
            // and ready to play. The shell switches the rotary nav to Chords and
            // sets its root + quality. (The optional `onPlayChord` audio hook
            // remains available for a future preview-on-tap; the chip's primary
            // gesture is now navigation.)
            onOpenChord(diatonic.chord)
        } label: {
            VStack(spacing: 2) {
                Text(diatonic.romanNumeral)
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.accent)
                Text(symbol)
                    .font(GKFont.body)
                    .foregroundStyle(GKColor.textPrimary)
            }
            .frame(minWidth: 52)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(GKColor.textSecondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        // Spell out the chip for VoiceOver: "Five chord, G major" reads better
        // than "V, G". We keep it concise, and add a hint for the cross-link.
        .accessibilityLabel("\(diatonic.romanNumeral) chord, \(symbol)")
        .accessibilityHint("Opens in the Chords tool")
    }

    // MARK: - View scale cross-link

    /// "View scale" — a discrete chip that opens the selected key's scale in the
    /// Scales tool. The key's scale is the one the wheel's selection represents
    /// (major key → major scale, minor key → natural minor), via the view model's
    /// `scale(for:)`, so the two tools always agree.
    private var viewScaleButton: some View {
        Button {
            onOpenScale(viewModel.scale(for: viewModel.selectedKey))
        } label: {
            Label("View scale", systemImage: "music.note.list")
                .font(GKFont.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(GKColor.accent.opacity(0.18))
                )
                .foregroundStyle(GKColor.accent)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this key's scale in the Scales tool")
    }

    // MARK: - Small helper

    /// A consistent little section caption ("Key signature", "Diatonic chords").
    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(GKFont.caption)
            .foregroundStyle(GKColor.textSecondary)
            // Uppercase + tracking gives a tidy "label" look without a new font.
            .textCase(.uppercase)
    }
}
