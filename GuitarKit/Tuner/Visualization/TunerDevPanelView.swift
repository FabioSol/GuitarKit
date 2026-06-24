//
//  TunerDevPanelView.swift
//  GuitarKit
//
//  The DEVELOPER-ONLY A/B panel (slice #07). A small sheet that flips the live
//  `TunerDevConfig`: pick the visualization, drag the in-tune threshold, drag the
//  smoothing. The Tuner applies each change immediately so we can feel the
//  difference while playing a real string.
//
//  Like `TunerDevConfig`, this entire file is `#if DEBUG` — it does not exist in
//  release builds, so there's no risk of a shipping user reaching it.
//

#if DEBUG
import SwiftUI

struct TunerDevPanelView: View {

    /// The shared live knobs. `@Bindable` gives us two-way `$bindings` into an
    /// `@Observable` object so the sliders/picker write straight back to it.
    @Bindable var config: TunerDevConfig

    /// Closes the sheet.
    var onClose: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                // ALGORITHM — which pitch detector runs (A/B them on a guitar).
                Section("Detection — algorithm") {
                    Picker("Algorithm", selection: $config.algorithm) {
                        ForEach(PitchAlgorithm.allCases, id: \.self) { algo in
                            Text(algo.label).tag(algo)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Ensemble cross-checks MPM + YIN (most robust); single algorithms are lighter.")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }

                // IN-TUNE THRESHOLD — how forgiving "in tune" is, in cents.
                Section("In-tune threshold") {
                    Slider(value: $config.inTuneThresholdCents, in: 1...15, step: 1) {
                        Text("Threshold")
                    } minimumValueLabel: {
                        Text("1¢")
                    } maximumValueLabel: {
                        Text("15¢")
                    }
                    Text("± \(Int(config.inTuneThresholdCents))¢ counts as in tune")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }

                // CLARITY GATE — how periodic a signal must be to register.
                Section("Detection — clarity gate") {
                    Slider(value: $config.clarityThreshold, in: 0.3...0.95, step: 0.05) {
                        Text("Clarity")
                    } minimumValueLabel: {
                        Text("catch")
                    } maximumValueLabel: {
                        Text("strict")
                    }
                    Text("Min clarity \(config.clarityThreshold, specifier: "%.2f") — lower catches more guitar, higher rejects more noise")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }

                // LEVEL GATE — the quietest signal we'll analyze.
                Section("Detection — level gate") {
                    Slider(value: $config.levelGateDB, in: -70...(-30), step: 1) {
                        Text("Level")
                    } minimumValueLabel: {
                        Text("quiet")
                    } maximumValueLabel: {
                        Text("loud")
                    }
                    Text("Gate \(Int(config.levelGateDB)) dBFS — lower hears the decaying tail of a plucked note")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }

                // SMOOTHING — the detector's EMA factor (jittery ↔ sluggish).
                Section("Smoothing") {
                    Slider(value: $config.smoothing, in: 0.05...1, step: 0.05) {
                        Text("Smoothing")
                    } minimumValueLabel: {
                        Text("smooth")
                    } maximumValueLabel: {
                        Text("snappy")
                    }
                    Text("EMA factor \(config.smoothing, specifier: "%.2f") — lower is smoother but laggier")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }

                Section {
                    Text("Developer build only — these controls are compiled out of release.")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }
            }
            .navigationTitle("Tuner Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }
}

#Preview {
    TunerDevPanelView(config: TunerDevConfig())
}
#endif
