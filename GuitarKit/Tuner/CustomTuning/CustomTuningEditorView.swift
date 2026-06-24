//
//  CustomTuningEditorView.swift
//  GuitarKit
//
//  The custom-tuning editor sheet (slice #12, PRD stories 26–32). It opens seeded
//  with the current tuning's open-string notes (a "duplicate to edit" starting
//  point), lets the player nudge each string ±1 semitone, hear a string (tone
//  generator) or capture it by playing (detector), warns gently if a string is
//  pushed wildly out of range, and saves under an auto-suggested name.
//
//  PRESENTATIONAL + LOCAL STATE ONLY:
//  The editor owns the in-progress `strings`/`name` while open (its own `@State`),
//  but it does NOT own persistence or audio. It reports intent through callbacks —
//  `onHear` (play a note), `detectedNote` (what's the mic hearing right now, for
//  capture), and `onSave` (persist the finished tuning). The presenter (the Tuner)
//  wires those to the real tone generator, detector, and CustomTuningStore.
//

import SwiftUI

struct CustomTuningEditorView: View {

    // MARK: Inputs

    /// The open-string notes to start from (a duplicate of the current tuning, or
    /// a blank instrument-shaped set). Low → high.
    let initialStrings: [Note]

    /// The instrument being tuned — supplies the home reference for the gentle
    /// out-of-range check, and its name for the warning copy.
    let instrument: Instrument

    /// Play a string's pitch so the player can hear what they're dialing in.
    var onHear: (Note) -> Void = { _ in }

    /// What note is the mic hearing right now (for capture-by-playing), or nil.
    /// The capture button writes this into the selected slot.
    var detectedNote: () -> Note? = { nil }

    /// Persist the finished tuning.
    let onSave: (Tuning) -> Void

    // MARK: Local editing state

    @Environment(\.dismiss) private var dismiss

    /// The strings being edited (seeded from `initialStrings` in `init`).
    @State private var strings: [Note]

    /// The tuning's name (seeded from the auto-suggested spelling; the player can
    /// override it before saving).
    @State private var name: String

    init(
        initialStrings: [Note],
        instrument: Instrument,
        onHear: @escaping (Note) -> Void = { _ in },
        detectedNote: @escaping () -> Note? = { nil },
        onSave: @escaping (Tuning) -> Void
    ) {
        self.initialStrings = initialStrings
        self.instrument = instrument
        self.onHear = onHear
        self.detectedNote = detectedNote
        self.onSave = onSave
        _strings = State(initialValue: initialStrings)
        _name = State(initialValue: CustomTuningSupport.autoSuggestedName(for: initialStrings))
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Tuning name", text: $name)
                        .font(GKFont.body)
                }

                Section("Strings (low → high)") {
                    ForEach(strings.indices, id: \.self) { index in
                        stringRow(index)
                    }
                }

                // Gentle, NON-BLOCKING out-of-range warning (you can still save).
                if CustomTuningSupport.isOutOfRange(strings: strings, for: instrument) {
                    Section {
                        Label(
                            "Some strings are more than an octave from \(instrument.name)'s usual range. You can still save.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.sharp)
                    }
                }
            }
            .navigationTitle("Custom Tuning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    // MARK: - String row

    private func stringRow(_ index: Int) -> some View {
        HStack(spacing: 12) {
            // The current note name (e.g. "D2"), steady tabular digits.
            Text(strings[index].name)
                .font(GKFont.liveNumeric)
                .tabularNumbers()
                .frame(width: 56, alignment: .leading)

            // ±1 semitone stepper — the primary editing control.
            Stepper(
                "",
                value: midiBinding(index),
                in: 0...127
            )
            .labelsHidden()

            Spacer()

            // Hear this string's pitch.
            Button {
                onHear(strings[index])
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .buttonStyle(.plain)
            .foregroundStyle(GKColor.accent)
            .accessibilityLabel("Hear \(strings[index].name)")

            // Capture this string from what the mic hears (optional).
            Button {
                if let heard = detectedNote() {
                    strings[index] = heard
                }
            } label: {
                Image(systemName: "mic")
            }
            .buttonStyle(.plain)
            .foregroundStyle(GKColor.textSecondary)
            .accessibilityLabel("Capture string \(index + 1) by playing it")
        }
    }

    // MARK: - Helpers

    /// A two-way binding from a string's MIDI number to its `Note`, so the Stepper
    /// can nudge by ±1 semitone (±1 MIDI) while we keep `Note` as the model.
    private func midiBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { strings[index].midiNumber },
            set: { strings[index] = Note.from(midiNumber: $0) }
        )
    }

    /// Build the `Tuning` and hand it to the presenter to persist. A blank name
    /// falls back to the auto-suggested spelling so we never save an unnamed tuning.
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty
            ? CustomTuningSupport.autoSuggestedName(for: strings)
            : trimmed
        onSave(Tuning(name: finalName, category: .alternate, strings: strings))
        dismiss()
    }
}

#Preview {
    CustomTuningEditorView(
        initialStrings: [
            Note(pitchClass: .e, octave: 2), Note(pitchClass: .a, octave: 2),
            Note(pitchClass: .d, octave: 3), Note(pitchClass: .g, octave: 3),
            Note(pitchClass: .b, octave: 3), Note(pitchClass: .e, octave: 4)
        ],
        instrument: InstrumentLibrary.guitar6,
        onSave: { print("save \($0.name)") }
    )
}
