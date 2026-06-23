//
//  MicDeniedView.swift
//  GuitarKit
//
//  The friendly, recoverable "you denied the mic" state (PRD story 63). Once
//  permission is denied, calling the request API again does nothing — the only
//  way back is the Settings app. So instead of a dead end, we explain the
//  situation and offer a one-tap deep link to this app's Settings page.
//

import SwiftUI
import UIKit

struct MicDeniedView: View {

    /// `openURL` is SwiftUI's environment action for opening links/URLs. We use
    /// it to jump to the Settings app. Reading it from the environment (rather
    /// than calling UIKit directly in the view body) keeps the view declarative.
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "mic.slash")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(GKColor.textSecondary)

                VStack(spacing: 12) {
                    Text("Microphone is off")
                        .font(GKFont.title)
                        .foregroundStyle(GKColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("GuitarKit needs your microphone to hear the notes you play. You can turn it back on in Settings.")
                        .font(GKFont.body)
                        .foregroundStyle(GKColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button(action: openSettings) {
                    Text("Open Settings")
                        .font(GKFont.title)
                        .foregroundStyle(GKColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .gkGlass(in: Capsule())
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
    }

    /// Build the URL to *this app's* page in the Settings app and open it.
    ///
    /// `UIApplication.openSettingsURLString` is Apple's special URL string that
    /// deep-links straight to the current app's settings (where the Microphone
    /// toggle lives). We convert it to a `URL` and hand it to `openURL`.
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
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
    MicDeniedView()
}
