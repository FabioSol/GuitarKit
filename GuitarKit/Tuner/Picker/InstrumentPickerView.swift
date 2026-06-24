//
//  InstrumentPickerView.swift
//  GuitarKit
//
//  The instrument/tuning picker SHEET (PRD "Picker & persistence"). Tapping the
//  selector pill on the Tuner face presents this. It's a vertical accordion:
//
//    ┌──────────────────────────────────────────┐
//    │  Most-used                                │  ← pinned group at the TOP,
//    │    Guitar · Standard                      │     ordered by usage (seeded so
//    │    Bass · Standard                        │     it's non-empty on a fresh
//    ├──────────────────────────────────────────┤     install, then washes out)
//    │  ▾ Guitar            (currently selected, │
//    │      Standard                  expanded)  │
//    │      Standard / Drop / Open / Alternate…  │  ← presets grouped by category
//    │      ＋ Create custom                      │
//    │  ▸ 7-String Guitar     (collapsed)        │
//    │  ▸ Bass                (collapsed)        │  ← all instruments in canonical
//    │  ▸ …                                      │     InstrumentLibrary.all order
//    └──────────────────────────────────────────┘
//
//  WHY A `List` OF `DisclosureGroup`s?
//  `List` gives us the grouped/scrolling chrome, Dynamic Type and accessibility
//  for free; `DisclosureGroup` is SwiftUI's built-in expand/collapse row — exactly
//  the "vertical accordion" the PRD asks for. We drive each group's expanded state
//  from our own `@State` so we can start the *current* instrument open and the
//  rest closed, and so tapping a header toggles just that one.
//
//  WHAT THIS VIEW DOES NOT DO:
//  It owns no durable state and performs no persistence. It's handed the current
//  selection and two callbacks (`onSelect`, `onCreateCustom`); recording usage and
//  restoring on launch live in `InstrumentSelectionStore`, wired by the presenter
//  (the Tuner). This keeps the view a thin, throwaway *description* of the picker.
//

import SwiftUI

struct InstrumentPickerView: View {

    // MARK: Inputs

    /// The instrument currently active in the Tuner. Used to (a) start that row
    /// expanded and (b) highlight it as selected.
    let selectedInstrument: Instrument

    /// The tuning currently active in the Tuner. Used to highlight the active
    /// preset row (and to know which row shows the checkmark).
    let selectedTuning: Tuning

    /// The ids of the player's most-used instruments, best-first, for the pinned
    /// group at the top. Supplied by the presenter from
    /// `InstrumentSelectionStore.mostUsedInstrumentIDs(limit:)` so this view stays
    /// free of persistence. Empty is fine — the group simply doesn't render.
    let mostUsedInstrumentIDs: [String]

    /// Called when the player taps a preset row. The presenter wires this to
    /// `TuningSessionModel.select(instrument:tuning:)` + the store's
    /// `recordSelection(...)`. After it fires we dismiss the sheet.
    let onSelect: (Instrument, Tuning) -> Void

    /// Called when the player taps "＋ Create custom" — opens the custom editor.
    let onCreateCustom: () -> Void

    /// Supplies the player's saved CUSTOM tunings for a given instrument (from the
    /// CustomTuningStore). Defaults to "none" so callers that don't have custom
    /// tunings keep working. Shown under a "Custom" sub-group with swipe-to-delete.
    let customTunings: (Instrument) -> [Tuning]

    /// Called to delete a custom tuning (swipe-to-delete). Default no-op.
    let onDeleteCustom: (Instrument, Tuning) -> Void

    // MARK: Environment + local state

    /// SwiftUI's dismiss action for the presenting sheet. We call it right after a
    /// selection so picking a tuning closes the picker and returns to the Tuner.
    @Environment(\.dismiss) private var dismiss

    /// Which instrument rows are currently expanded, tracked by instrument id.
    /// We seed it (in `init`) with just the currently-selected instrument so it
    /// starts open and every other row starts collapsed (the PRD's "current
    /// expanded, others collapsed"). A `Set` makes "is this row open?" a fast
    /// membership check.
    @State private var expandedInstrumentIDs: Set<String>

    // MARK: Init
    //
    // An explicit initializer for two reasons: so `onCreateCustom` can DEFAULT to
    // a no-op closure, AND so we can SEED the `@State` set from the passed-in
    // selection. Seeding `@State` from a parameter is the one Swift wrinkle here:
    // you assign to its underscore-prefixed storage (`_expandedInstrumentIDs`)
    // using `State(initialValue:)`, NOT to the property directly.
    init(
        selectedInstrument: Instrument,
        selectedTuning: Tuning,
        mostUsedInstrumentIDs: [String] = [],
        onSelect: @escaping (Instrument, Tuning) -> Void,
        onCreateCustom: @escaping () -> Void = {},
        customTunings: @escaping (Instrument) -> [Tuning] = { _ in [] },
        onDeleteCustom: @escaping (Instrument, Tuning) -> Void = { _, _ in }
    ) {
        self.selectedInstrument = selectedInstrument
        self.selectedTuning = selectedTuning
        self.mostUsedInstrumentIDs = mostUsedInstrumentIDs
        self.onSelect = onSelect
        self.onCreateCustom = onCreateCustom
        self.customTunings = customTunings
        self.onDeleteCustom = onDeleteCustom
        // Start with the active instrument's row expanded, all others collapsed.
        _expandedInstrumentIDs = State(initialValue: [selectedInstrument.id])
    }

    // MARK: Body

    var body: some View {
        // A NavigationStack gives us the title bar + a Done button slot. The sheet
        // presenter could also wrap us, but owning it here keeps the picker
        // self-contained for previews.
        NavigationStack {
            List {
                mostUsedSection
                allInstrumentsSection
            }
            .navigationTitle("Instrument")
            // `.inline` keeps the title compact — this is a focused picker sheet,
            // not a top-level screen.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A trailing Done button so the player can back out without
                // selecting anything (tapping a preset also dismisses).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Most-used (pinned) section

    /// The pinned group at the very top. We resolve each id back to a real
    /// `Instrument` (skipping any that no longer exist) and show a single tappable
    /// row per instrument that selects its CURRENT-or-default tuning. This is a
    /// fast "jump straight back to what I use" affordance; the full per-instrument
    /// preset list still lives in the accordion below.
    @ViewBuilder
    private var mostUsedSection: some View {
        // Resolve ids → instruments once. `compactMap` drops any unknown id. We
        // call `instrument(id:)` inside a closure (rather than passing it as a
        // function reference) so it runs in this main-actor view context — passing
        // the main-actor method directly would warn under the project's isolation.
        let mostUsed = mostUsedInstrumentIDs.compactMap { InstrumentLibrary.instrument(id: $0) }

        // Only render the section when there's something to show (a brand-new
        // install seeds it, so normally it's non-empty — but be defensive).
        if !mostUsed.isEmpty {
            Section("Most-used") {
                ForEach(mostUsed) { instrument in
                    // Pick the tuning this quick-row jumps to: the active tuning if
                    // it's the currently-selected instrument, else that
                    // instrument's home/default tuning.
                    let tuning = quickTuning(for: instrument)
                    Button {
                        choose(instrument, tuning)
                    } label: {
                        instrumentSummaryRow(instrument: instrument, tuning: tuning)
                    }
                    // Plain row tint, not the default blue button styling — this is
                    // a list row, not a call-to-action.
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The tuning a Most-used quick-row jumps to for `instrument`.
    private func quickTuning(for instrument: Instrument) -> Tuning {
        if instrument.id == selectedInstrument.id { return selectedTuning }
        return instrument.defaultTuning
            ?? Tuning(name: "Standard", category: .standard, strings: [])
    }

    // MARK: - All instruments (accordion) section

    /// Every instrument in canonical `InstrumentLibrary.all` order, each as an
    /// expand/collapse `DisclosureGroup`. The currently-selected instrument starts
    /// expanded (seeded in `init`); the rest collapsed.
    private var allInstrumentsSection: some View {
        Section("All instruments") {
            ForEach(InstrumentLibrary.all) { instrument in
                DisclosureGroup(
                    // Bind this group's open/closed state to membership in our
                    // `expandedInstrumentIDs` set. The custom binding lets us
                    // toggle exactly this id when the chevron is tapped.
                    isExpanded: expansionBinding(for: instrument)
                ) {
                    instrumentTunings(instrument)
                } label: {
                    instrumentHeaderRow(instrument)
                }
            }
        }
    }

    /// The header row for an instrument inside its disclosure group: the name, a
    /// subtle current-tuning subtitle when it's the active instrument, and a
    /// checkmark marking the active instrument.
    private func instrumentHeaderRow(_ instrument: Instrument) -> some View {
        let isActive = instrument.id == selectedInstrument.id
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(instrument.name)
                    .font(GKFont.body)
                    .foregroundStyle(GKColor.textPrimary)
                // Show the active tuning under the active instrument so the header
                // doubles as a status line.
                if isActive {
                    Text(selectedTuning.name)
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(GKColor.accent)
                    // Decorative: the row's accessibility label below already says
                    // "selected", so we hide the glyph from VoiceOver.
                    .accessibilityHidden(true)
            }
        }
        // One combined accessibility element per header, announcing selection.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isActive
                ? "\(instrument.name), selected, currently \(selectedTuning.name)"
                : instrument.name
        )
    }

    /// The expanded body of an instrument: its presets grouped by category under
    /// labelled sub-headers (Standard / Drop / Open / Alternate), then the
    /// "＋ Create custom" row.
    @ViewBuilder
    private func instrumentTunings(_ instrument: Instrument) -> some View {
        // Walk the four categories in their canonical enum order so the sub-groups
        // always appear Standard → Drop → Open → Alternate, regardless of the
        // order presets happen to be listed in the instrument.
        ForEach(TuningCategory.allCases, id: \.self) { category in
            // The presets in THIS instrument that file under THIS category,
            // preserving their declared order.
            let presets = instrument.tunings.filter { $0.category == category }
            if !presets.isEmpty {
                // A small grey sub-header so the player can see the grouping. We
                // use a plain Text row rather than a nested Section because we're
                // already inside a DisclosureGroup inside a Section.
                Text(categoryLabel(category))
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(presets, id: \.name) { tuning in
                    tuningRow(instrument: instrument, tuning: tuning)
                }
            }
        }

        // The player's saved CUSTOM tunings for this instrument, under their own
        // sub-header, each swipe-to-deletable.
        let customs = customTunings(instrument)
        if !customs.isEmpty {
            Text("Custom")
                .font(GKFont.caption)
                .foregroundStyle(GKColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(customs, id: \.name) { tuning in
                tuningRow(instrument: instrument, tuning: tuning)
                    // Swipe left to delete this custom tuning (story 32).
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDeleteCustom(instrument, tuning)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }

        // The "＋ Create custom" row — opens the editor seeded from the current
        // tuning. Quiet/secondary styling; discoverable + VoiceOver-reachable.
        Button {
            onCreateCustom()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Create custom")
            }
            .font(GKFont.body)
            // Dimmed to signal it's a secondary/forthcoming affordance.
            .foregroundStyle(GKColor.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create custom tuning for \(instrument.name)")
    }

    /// One tappable preset row. Highlights (checkmark + accent name) when it's the
    /// active instrument's active tuning. Tapping selects it and dismisses.
    private func tuningRow(instrument: Instrument, tuning: Tuning) -> some View {
        // A preset is "active" only when BOTH the instrument and the tuning match —
        // two instruments can both have a "Standard" preset.
        let isActive = instrument.id == selectedInstrument.id
            && tuning.name == selectedTuning.name

        return Button {
            choose(instrument, tuning)
        } label: {
            HStack {
                Text(tuning.name)
                    .font(GKFont.body)
                    // Tint the active preset's name with the accent for a clear,
                    // non-colour-only cue (the checkmark is the redundant signal).
                    .foregroundStyle(isActive ? GKColor.accent : GKColor.textPrimary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(GKColor.accent)
                        .accessibilityHidden(true)
                }
            }
            // Indent the preset rows slightly so they sit visually under their
            // category sub-header.
            .padding(.leading, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tuning.name)\(isActive ? ", selected" : "")")
        .accessibilityHint("Tunes \(instrument.name) to \(tuning.name)")
    }

    /// A compact "Instrument · Tuning" summary used by the Most-used quick-rows.
    private func instrumentSummaryRow(instrument: Instrument, tuning: Tuning) -> some View {
        let isActive = instrument.id == selectedInstrument.id
            && tuning.name == selectedTuning.name
        return HStack {
            Text(instrument.name)
                .font(GKFont.body)
                .foregroundStyle(GKColor.textPrimary)
            Text("·")
                .foregroundStyle(GKColor.textSecondary)
            Text(tuning.name)
                .font(GKFont.body)
                .foregroundStyle(GKColor.textSecondary)
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(GKColor.accent)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(instrument.name), \(tuning.name)\(isActive ? ", selected" : "")")
    }

    // MARK: - Actions

    /// Fire the selection callback, then dismiss the sheet. The single funnel for
    /// every tappable row so selection behaviour stays consistent.
    private func choose(_ instrument: Instrument, _ tuning: Tuning) {
        onSelect(instrument, tuning)
        dismiss()
    }

    // MARK: - Helpers

    /// A two-way `Binding<Bool>` for a single instrument's expanded state, backed
    /// by membership in `expandedInstrumentIDs`. Reading returns "is this id in the
    /// set?"; writing inserts/removes the id. This is what lets each DisclosureGroup
    /// expand/collapse independently while we still own the truth in one set.
    private func expansionBinding(for instrument: Instrument) -> Binding<Bool> {
        Binding(
            get: { expandedInstrumentIDs.contains(instrument.id) },
            set: { isOpen in
                if isOpen { expandedInstrumentIDs.insert(instrument.id) }
                else { expandedInstrumentIDs.remove(instrument.id) }
            }
        )
    }

    /// The human-facing label for a tuning category sub-header.
    private func categoryLabel(_ category: TuningCategory) -> String {
        switch category {
        case .standard:  return "Standard"
        case .drop:      return "Drop"
        case .open:      return "Open"
        case .alternate: return "Alternate"
        }
    }
}

// MARK: - Preview

#Preview {
    // A throwaway preview: open on the guitar, Standard tuning, with a seeded
    // most-used group. The callbacks just print so the preview is interactive.
    InstrumentPickerView(
        selectedInstrument: InstrumentLibrary.default,
        selectedTuning: InstrumentLibrary.default.defaultTuning
            ?? Tuning(name: "Standard", category: .standard, strings: []),
        mostUsedInstrumentIDs: ["guitar-6", "bass-4", "ukulele"],
        onSelect: { instrument, tuning in
            print("Selected \(instrument.name) · \(tuning.name)")
        },
        onCreateCustom: {
            print("Create custom tapped (no-op until slice #12)")
        }
    )
}
