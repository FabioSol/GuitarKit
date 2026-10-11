//
//  GKToggleStyle.swift
//  GuitarKit
//
//  A minimal custom toggle that avoids the iOS 26 Liquid Glass specular-
//  highlight animation (the "white element grows and fades" artifact on the
//  default switch style). Uses a plain capsule + circle thumb with a clean
//  spring transition — no glow, no scale pop.
//
//  Usage: apply `.toggleStyle(GKToggleStyle())` to any Toggle, or set it once
//  on a container with `.toggleStyle(GKToggleStyle())`.
//

import SwiftUI

struct GKToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                    .foregroundStyle(GKColor.textPrimary)
                Spacer()
                track(isOn: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
    }

    private func track(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? GKColor.accent : GKColor.textSecondary.opacity(0.25))
                .frame(width: 44, height: 26)

            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .padding(3)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: isOn)
    }
}
