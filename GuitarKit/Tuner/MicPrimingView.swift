//
//  MicPrimingView.swift
//  GuitarKit
//
//  The first-run "value screen" (PRD story 62). Shown ONCE, before the OS mic
//  prompt, to explain *why* GuitarKit wants the microphone — so the user
//  understands the upcoming system dialog and is far more likely to allow it.
//  Tapping Start triggers the real OS permission prompt.
//

import SwiftUI

struct MicPrimingView: View {

    /// Called when the user taps "Start tuning". The parent does the actual
    /// permission request (this view stays UI-only, which keeps it previewable
    /// and free of audio dependencies). A closure is the SwiftUI-idiomatic way
    /// to hand an action back to the parent.
    let onStart: () -> Void

    var body: some View {
        ZStack {
            // Same ambient backdrop the tools use, for visual continuity.
            backdrop

            VStack(spacing: 28) {
                Spacer()

                // A friendly hero glyph. The tuning fork ties to the tuner.
                Image(systemName: "tuningfork")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(GKColor.accent)
                    // A soft glow so the icon feels like the app's signature.
                    .shadow(color: GKColor.accent.opacity(0.5), radius: 20)

                // The value proposition — short, concrete, benefit-first.
                VStack(spacing: 12) {
                    Text("Tune any instrument")
                        .font(GKFont.largeTitle)
                        .foregroundStyle(GKColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("GuitarKit listens through your mic to detect each note and guide you in tune. Audio stays on your device — nothing is recorded or sent anywhere.")
                        .font(GKFont.body)
                        .foregroundStyle(GKColor.textSecondary)
                        .multilineTextAlignment(.center)
                        // Constrain the line length for comfortable reading.
                        .padding(.horizontal, 32)
                }

                Spacer()

                // The single, obvious call to action. Tapping it asks the parent
                // to fire the OS prompt.
                Button(action: onStart) {
                    Text("Start tuning")
                        .font(GKFont.title)
                        .foregroundStyle(GKColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                // Glass chrome on the button, per the design system (the button
                // is "functional chrome", a legal place for glass).
                .gkGlass(in: Capsule())
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea()
        // Group for VoiceOver so the screen reads as one coherent unit.
        .accessibilityElement(children: .contain)
    }

    /// The shared ambient gradient — the app's subtle accent-tinted backdrop.
    private var backdrop: some View {
        LinearGradient(
            colors: [GKColor.accent.opacity(0.18), GKColor.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    MicPrimingView(onStart: {})
}
