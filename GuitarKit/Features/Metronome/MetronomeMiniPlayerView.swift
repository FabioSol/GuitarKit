//
//  MetronomeMiniPlayerView.swift
//  GuitarKit
//
//  Compact floating control that appears when the metronome is active while
//  the user is on a different tool.
//
//  Playing  → single round pause button
//  Paused   → two round buttons: play (resume) and stop (dismisses this view)
//

import SwiftUI

struct MetronomeMiniPlayerView: View {

    let isPlaying: Bool
    let onToggle: () -> Void   // pause / resume
    let onStop: () -> Void     // stop + dismiss

    var body: some View {
        HStack(spacing: 6) {
            miniButton(icon: isPlaying ? "pause.fill" : "play.fill",
                       action: onToggle)

            if !isPlaying {
                miniButton(icon: "xmark", action: onStop)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isPlaying)
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }

    private func miniButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GKColor.accent)
                .frame(width: 30, height: 30)
                .background(GKColor.accent.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
