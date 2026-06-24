//
//  SettingsView.swift
//  GuitarKit
//
//  The grouped Settings screen (PRD "Settings" section / issue #22). It shows the
//  app's GLOBAL, PERSISTENT preferences as a standard iOS `Form`, grouped exactly
//  into the PRD's sections: Tuning, Feedback, Appearance, Instrument, an Advanced
//  disclosure (sweetened profile + sensitivity + experimental flags), and About.
//
//  WHY A `Form` (not a hand-rolled VStack)?
//  `Form` is SwiftUI's purpose-built container for settings/preference screens.
//  It gives us the familiar grouped-list look, correct spacing, Dynamic Type, and
//  accessibility for free — and `Section` headers/footers handle the grouping the
//  PRD asks for. Building this by hand would re-invent all of that worse.
//
//  WHAT THIS VIEW DOES NOT DO:
//  It holds NO state of its own — every control is bound straight to the shared
//  `SettingsStore`. The view is a thin, throwaway *description* of the settings;
//  the durable values (and their persistence) live in the store. The store is
//  passed in by whoever presents this screen (the app shell), so previews/tests
//  can supply a throwaway one.
//

import SwiftUI

struct SettingsView: View {

    /// The shared preferences object. `@Bindable` is the `@Observable`-era tool
    /// that lets us make two-way `$` bindings (for Toggles, Pickers, Steppers)
    /// to a reference type we were *handed* rather than one we own. (We don't use
    /// `@State` here because this view doesn't own the store's lifetime — the app
    /// shell does; we just read and mutate it.)
    @Bindable var store: SettingsStore

    /// Lets the About section's "Done"-style dismissal and any sheet wrapper close
    /// cleanly. SwiftUI injects this; we read it so a toolbar Done button (added by
    /// the presenter) has something to call. Kept here for completeness.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            tuningSection
            feedbackSection
            appearanceSection
            instrumentSection
            metronomeSection
            advancedSection
            aboutSection
        }
        // The screen title. `.navigationTitle` expects this view to sit inside a
        // navigation container, which the presenter supplies (e.g. a
        // `NavigationStack` inside the sheet).
        .navigationTitle("Settings")
    }

    // MARK: - Tuning

    /// Reference-pitch calibration. The everyday control is here; the rarely-used
    /// sweetened/sensitivity knobs live under Advanced (PRD groups them so).
    private var tuningSection: some View {
        Section {
            // A Stepper gives precise ±1 Hz control over the reference pitch, which
            // suits a calibration value better than a slider you can fat-finger.
            // The `value:in:step:` form clamps the stepper to the legal A4 band, and
            // the store re-clamps through `ReferencePitch` as a belt-and-braces.
            Stepper(value: $store.referencePitchHz,
                    in: ReferencePitch.minHz...ReferencePitch.maxHz,
                    step: 1) {
                // A two-line label: what it is, plus the live value. We use the
                // tabular-figures helper so the number doesn't jitter as it changes.
                HStack {
                    Text("Reference Pitch")
                        .font(GKFont.body)
                    Spacer()
                    Text("A = \(Int(store.referencePitchHz)) Hz")
                        .font(GKFont.body)
                        .foregroundStyle(GKColor.textSecondary)
                        .tabularNumbers()
                }
            }
        } header: {
            Text("Tuning")
        } footer: {
            Text("Concert pitch is A = 440 Hz. Adjust only to match another instrument or recording.")
        }
    }

    // MARK: - Feedback

    /// Haptics + sound. Per the PRD the app is silent by default, so the sound
    /// toggle starts off; the confirmation-sound picker is only meaningful when
    /// sound is on, so we disable it otherwise rather than hiding it (keeps the
    /// layout stable and the option discoverable).
    private var feedbackSection: some View {
        Section("Feedback") {
            Toggle("Haptics", isOn: $store.hapticsEnabled)

            Toggle("Sound", isOn: $store.soundEnabled)

            Picker("Confirmation Sound", selection: $store.confirmationSound) {
                // `ForEach` over `allCases` builds one row per enum option. The enum
                // is `Identifiable` (id: self) so SwiftUI can tell the rows apart.
                ForEach(ConfirmationSound.allCases) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }
            // Greyed out until sound is enabled — the choice has no effect while
            // silent, and disabling communicates that clearly.
            .disabled(!store.soundEnabled)
        }
    }

    // MARK: - Appearance

    /// Theme only. The accent is GuitarKit's fixed purple signature — not a user
    /// choice — so there's no accent control here. (The store still carries a
    /// single-purple `accent` token for forward-compat, but it's never surfaced.)
    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $store.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
        }
    }

    // MARK: - Instrument

    /// Global handedness mirror + default note spelling.
    private var instrumentSection: some View {
        Section("Instrument") {
            Picker("Handedness", selection: $store.handedness) {
                ForEach(Handedness.allCases) { hand in
                    Text(hand.displayName).tag(hand)
                }
            }

            Picker("Default Labeling", selection: $store.defaultLabeling) {
                ForEach(NoteLabeling.allCases) { labeling in
                    Text(labeling.displayName).tag(labeling)
                }
            }
        }
    }

    // MARK: - Metronome

    /// The metronome's click timbre + the per-beat haptic. These live here (rather
    /// than on the metronome face) to keep that screen focused on tempo + meter.
    private var metronomeSection: some View {
        Section {
            Picker("Click Sound", selection: $store.metronomeSoundSet) {
                ForEach(MetronomeSoundSet.allCases, id: \.self) { set in
                    Text(set.label).tag(set)
                }
            }

            Toggle("Per-Beat Haptic", isOn: $store.metronomeHapticsEnabled)
        } header: {
            Text("Metronome")
        } footer: {
            Text("Turn on the per-beat haptic and mute the beats for silent practice — feel the pulse with no sound.")
        }
    }

    // MARK: - Advanced (disclosure)

    /// The rarely-touched expert controls, tucked behind a `DisclosureGroup` so
    /// they don't clutter the main list (PRD: "Advanced options are tucked under a
    /// disclosure"). This is also where the otherwise-hidden sweetened-tuning UI
    /// lives. A `DisclosureGroup` is a row that expands/collapses to reveal its
    /// content — exactly the affordance the PRD asks for.
    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced") {
                // — Sweetened tuning profile —
                Toggle("Sweetened Tuning", isOn: $store.sweetenedTuningEnabled)

                // — In-tune sensitivity —
                Picker("In-Tune Sensitivity", selection: $store.inTuneSensitivity) {
                    ForEach(InTuneSensitivity.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }

                // — Experimental feature flags —
                // A small visual sub-heading so it's clear these are experiments.
                Text("Experimental")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)

                Toggle("Hero Visualization", isOn: $store.experimentalHeroVisualization)
                Toggle("Finger-Number Labels", isOn: $store.experimentalFingerNumberLabels)
                Toggle("Reactive Backdrop", isOn: $store.experimentalReactiveBackdrop)

                #if DEBUG
                // DEVELOPER-ONLY rows. Wrapped in `#if DEBUG` so the entire control
                // is compiled OUT of release builds (PRD: dev flags don't ship).
                // The matching store property is also DEBUG-only, so both vanish
                // together in release.
                Text("Developer")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
                Toggle("Diagnostics Overlay", isOn: $store.debugShowDiagnosticsOverlay)
                #endif

                // — Reset —
                // A destructive-styled button to restore factory defaults. `role:
                // .destructive` tints it red and gives the right accessibility
                // semantics; tapping calls the store's `reset()`.
                Button("Reset to Defaults", role: .destructive) {
                    store.reset()
                }
            }
        }
    }

    // MARK: - About

    /// App identity + the required privacy statement + support rows. The version
    /// and build come from the app's `Info.plist` via `Bundle.main`, so they stay
    /// correct automatically as we bump versions — no hard-coded number to forget.
    private var aboutSection: some View {
        Section("About") {
            // Version + build. `CFBundleShortVersionString` is the user-facing
            // version ("1.0"); `CFBundleVersion` is the build number ("42").
            LabeledContent("Version", value: Self.versionString)

            // THE PRIVACY STATEMENT (acceptance criterion): it must state
            // on-device / no-tracking / no-accounts. We say all three explicitly.
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy")
                    .font(GKFont.body)
                Text("GuitarKit runs entirely on-device. There is no tracking, no analytics, and no accounts — your audio and preferences never leave your iPhone.")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
            }
            // Combine the two Texts into one accessibility element so VoiceOver
            // reads the heading and statement together.
            .accessibilityElement(children: .combine)

            // Support rows. These are placeholders for now — wiring them to the App
            // Store review prompt and a mail composer is a later, tiny task.
            // TODO(#22 follow-up): open the App Store review sheet via SKStoreReviewController / a write-a-review deep link.
            Button("Rate GuitarKit") {
                // TODO: present the rating prompt.
            }

            // TODO(#22 follow-up): open a mailto: or in-app mail composer to the support address.
            Button("Contact Support") {
                // TODO: open the contact channel.
            }
        }
    }

    // MARK: - Helpers

    /// Builds the "1.0 (42)" version string from the bundle. `static` because it
    /// needs no instance state — it just reads the bundle. We fall back to "—" if
    /// either key is somehow missing so the row never shows an empty value.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

// MARK: - Preview

#Preview {
    // Wrap in a NavigationStack so the title renders, and hand in a throwaway
    // store (the default `.standard`-backed one is fine for a preview).
    NavigationStack {
        SettingsView(store: SettingsStore())
    }
}
