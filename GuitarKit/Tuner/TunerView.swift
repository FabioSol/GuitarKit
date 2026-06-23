//
//  TunerView.swift
//  GuitarKit
//
//  The Tuner tab's top-level screen and the orchestrator for this slice. It
//  decides, based on first-run state + mic permission, WHICH sub-screen to show:
//
//      first launch & undetermined  → MicPrimingView   (value screen → prompt)
//      granted                      → live level meter  (audio flows!)
//      denied                       → MicDeniedView     (recoverable, → Settings)
//
//  Later slices replace the "granted" content (the meter) with the real tuner
//  hero, but the permission/lifecycle scaffolding here stays.
//

import SwiftUI

struct TunerView: View {

    // MARK: Owned state
    //
    // `@State` for reference types uses the `@Observable` macro under the hood:
    // SwiftUI keeps these alive for the view's lifetime and re-renders when
    // their observed properties change. This view OWNS the permission model and
    // the audio engine.

    /// The microphone-permission model. Drives which sub-screen we show.
    @State private var permission = MicrophonePermission()

    /// The audio capture engine. Its `level` feeds the meter and its raw buffers
    /// feed the pitch detector below.
    @State private var engine = AudioInputEngine()

    /// The pitch detector. We attach it to the engine's buffer stream so it sees
    /// the same audio, then bind the readout to its published `reading`.
    @State private var detector = MPMPitchDetector()

    /// Whether the user has already seen the first-run priming screen. We read
    /// the persisted flag once into view state, then flip it when priming
    /// completes. A plain `Bool` (not the struct) so SwiftUI re-renders on change.
    @State private var hasCompletedPriming = FirstRunFlag().hasCompletedPriming

    /// `scenePhase` tells us when the app moves between active/inactive/background.
    /// We watch it so that when the user returns from the Settings app (where
    /// they may have just granted the mic) we re-check permission and start audio.
    @Environment(\.scenePhase) private var scenePhase

    // MARK: Body

    var body: some View {
        // Choose the sub-screen. `Group` lets us `switch`/`if` and still attach
        // shared modifiers (`.onChange`, `.task`) to the whole thing.
        Group {
            if shouldShowPriming {
                // FIRST RUN: explain value, then (on Start) request permission.
                MicPrimingView(onStart: handleStartTapped)
            } else {
                switch permission.state {
                case .undetermined:
                    // Returning user who somehow never decided (rare). Show the
                    // priming screen's CTA path again rather than a blank meter.
                    MicPrimingView(onStart: handleStartTapped)
                case .granted:
                    grantedContent
                case .denied:
                    MicDeniedView()
                }
            }
        }
        // When permission becomes granted, (re)start the engine; when it leaves
        // granted, stop it. `.onChange(of:)` fires whenever the value changes.
        .onChange(of: permission.state) { _, newState in
            syncEngine(to: newState)
        }
        // On first appearance, if we already have permission (returning user),
        // start capturing immediately so the meter is live.
        .task {
            if !shouldShowPriming {
                syncEngine(to: permission.state)
            }
        }
        // Re-check permission when the app becomes active again (e.g. returning
        // from Settings after flipping the mic toggle). `.onChange` of scenePhase
        // is the standard place to react to foreground/background transitions.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                permission.refresh()
            }
        }
    }

    // MARK: Sub-screens

    /// What we show once the mic is granted: the live pitch readout (note name +
    /// frequency + cents), with the input meter kept underneath as a secondary
    /// "is sound getting in?" signal. The headstock hero replaces this in #06.
    private var grantedContent: some View {
        ZStack {
            backdrop

            VStack(spacing: 32) {
                // The tracer-bullet payoff: live detected pitch on screen.
                RawPitchReadoutView(reading: detector.reading)

                // Keep the level meter as a small secondary indicator — handy
                // while developing detection (you can see signal even when no
                // confident pitch is found yet).
                InputLevelMeter(level: engine.level)
                    .padding(.horizontal, 40)
            }
            .padding()
        }
        .ignoresSafeArea()
    }

    // MARK: Logic

    /// Show the priming screen only on a genuine first run that hasn't decided
    /// yet. (If a returning user previously granted/denied, skip straight to the
    /// relevant state even if the flag somehow wasn't set.)
    private var shouldShowPriming: Bool {
        !hasCompletedPriming && permission.state == .undetermined
    }

    /// User tapped "Start tuning" on the priming screen. Mark priming done
    /// (so it never shows again) and fire the OS permission prompt.
    private func handleStartTapped() {
        // Persist that we've shown priming, and reflect it in view state so the
        // priming screen won't reappear after the prompt resolves.
        let flag = FirstRunFlag()
        flag.markPrimingComplete()
        hasCompletedPriming = true

        // Request permission. `Task { ... }` launches the async work; when it
        // finishes, `permission.state` updates and `.onChange` starts the engine
        // if we were granted.
        Task {
            await permission.request()
        }
    }

    /// Start or stop the audio engine to match the permission state.
    private func syncEngine(to state: MicPermissionState) {
        switch state {
        case .granted:
            // Subscribe the detector to the engine's buffers BEFORE starting, so
            // it's wired up the moment audio begins flowing. Re-attaching is
            // harmless (it just re-sets the single buffer handler).
            detector.attach(to: engine)
            do {
                try engine.start()
            } catch {
                // Starting can fail if another app holds the mic. We don't crash;
                // the readout simply stays idle. A future slice can surface a
                // gentle error; for this slice silence is acceptable.
                print("AudioInputEngine failed to start: \(error)")
            }
        case .denied, .undetermined:
            engine.stop()
            // Clear any lingering reading so a stale note doesn't hang on screen.
            detector.reset()
        }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [GKColor.accent.opacity(0.18), GKColor.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    TunerView()
}
