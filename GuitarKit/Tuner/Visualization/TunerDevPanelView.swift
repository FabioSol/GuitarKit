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

    /// Records labelled clips for the pitch benchmark (`nil` → section hidden,
    /// e.g. in previews).
    var recorder: PitchClipRecorder?

    /// The current tuning's strings — what a clip can be labelled as.
    var targets: [PitchTarget] = []

    /// Builds a clip's label + replay context (band, calibration, tuning).
    var makeClipMetadata: ((PitchTarget?, PitchClipRecorder.Pluck?,
                            PitchClipRecorder.Background) -> PitchClipRecorder.Metadata)?

    /// Closes the sheet.
    var onClose: () -> Void = {}

    // Clip label choices. `-1` = a noise-only clip (nothing plucked).
    @State private var clipTargetIndex = 0
    @State private var clipPluck: PitchClipRecorder.Pluck = .medium
    @State private var clipBackground: PitchClipRecorder.Background = .quiet

    var body: some View {
        NavigationStack {
            Form {
                if let recorder, let makeClipMetadata {
                    recordingSection(recorder, makeClipMetadata)
                }

                // ENGINE — gated (per-frame gates) vs probabilistic (a belief
                // over which string is ringing, built up across frames).
                Section("Detection — engine") {
                    Picker("Engine", selection: $config.engine) {
                        Text("Gated").tag(PitchEngine.gated)
                        Text("Probabilistic").tag(PitchEngine.probabilistic)
                    }
                    .pickerStyle(.segmented)
                    Text(config.engine == .gated
                         ? "Per-frame gates: each frame must pass clarity, level and the harmonic check."
                         : "Tracks which string is ringing; evidence builds up across frames and survives a voice over the string. Targeted mode only.")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }

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

                // PREPROCESSING — the band-pass that rescues the low strings.
                // On/off only: the corners are derived from the selected tuning
                // (DetectionBand), so there is nothing to hand-tune here.
                Section("Detection — preprocessing") {
                    Toggle("Band-pass filter", isOn: $config.preprocessEnabled)
                    Text("Corners follow the selected tuning: high-pass under the lowest string, low-pass with harmonic headroom above the highest.")
                        .font(GKFont.caption)
                        .foregroundStyle(GKColor.textSecondary)
                }

                // HARMONIC CHECK — refuse frames that don't look like one
                // harmonic source (voices, chords, clicks). Targeted mode only.
                Section("Detection — harmonic check") {
                    Slider(value: $config.harmonicGate, in: 0...0.9, step: 0.05) {
                        Text("Harmonic gate")
                    } minimumValueLabel: {
                        Text("off")
                    } maximumValueLabel: {
                        Text("strict")
                    }
                    Text(config.harmonicGate == 0
                         ? "Off — any clear pitch can start a note"
                         : "Gate \(config.harmonicGate, specifier: "%.2f") — notes must look like one harmonic source (blocks voices, chords). Targeted mode only.")
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
            .onAppear {
                // A tuning switch can shrink the string list under the picker.
                if !targets.indices.contains(clipTargetIndex) { clipTargetIndex = 0 }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }

    // MARK: Recording

    /// Record labelled clips of real plucks for `PitchBench/` (see its README).
    @ViewBuilder
    private func recordingSection(
        _ recorder: PitchClipRecorder,
        _ makeMetadata: @escaping (PitchTarget?, PitchClipRecorder.Pluck?,
                                   PitchClipRecorder.Background) -> PitchClipRecorder.Metadata
    ) -> some View {
        Section {
            Picker("String", selection: $clipTargetIndex) {
                ForEach(targets.indices, id: \.self) { i in
                    Text("\(targets[i].note.name) · \(targets[i].frequencyHz, specifier: "%.1f") Hz").tag(i)
                }
                Text("Noise only (don't pluck)").tag(-1)
            }
            if clipTargetIndex >= 0 {
                Picker("Pluck", selection: $clipPluck) {
                    ForEach(PitchClipRecorder.Pluck.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Picker("Background", selection: $clipBackground) {
                ForEach(PitchClipRecorder.Background.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Length", selection: Bindable(recorder).clipSeconds) {
                Text("4 s").tag(4.0)
                Text("6 s").tag(6.0)
                Text("10 s").tag(10.0)
            }
            .pickerStyle(.segmented)

            if recorder.isRecording {
                HStack {
                    ProgressView(value: min(recorder.elapsed / recorder.clipSeconds, 1))
                    Button("Cancel", role: .cancel) { recorder.cancel() }
                }
                Text(clipTargetIndex >= 0 ? "Pluck the string once and let it ring…" : "Recording the room…")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
            } else {
                Button {
                    let target = targets.indices.contains(clipTargetIndex) ? targets[clipTargetIndex] : nil
                    recorder.start(makeMetadata(target, clipPluck, clipBackground))
                } label: {
                    Label("Record clip", systemImage: "record.circle")
                }
            }

            if let error = recorder.lastError {
                Text(error).font(GKFont.caption).foregroundStyle(.red)
            }

            if !recorder.clips.isEmpty {
                ShareLink(items: recorder.allFiles) {
                    Label("Share \(recorder.clips.count) clips (.wav + .json)", systemImage: "square.and.arrow.up")
                }
                ForEach(recorder.clips, id: \.self) { clip in
                    Text(clip.deletingPathExtension().lastPathComponent)
                        .font(.caption.monospaced())
                        .swipeActions { Button("Delete", role: .destructive) { recorder.delete(clip) } }
                }
            }
        } header: {
            Text("Benchmark clips")
        } footer: {
            Text("Records what the tuner hears, for replay in the pitch benchmark. Copy shared clips into PitchBench/recordings/.")
        }
    }
}

#Preview {
    TunerDevPanelView(config: TunerDevConfig())
}
#endif
