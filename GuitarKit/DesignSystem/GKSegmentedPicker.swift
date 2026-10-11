//
//  GKSegmentedPicker.swift
//  GuitarKit
//
//  A custom segmented control that avoids the iOS 26 Liquid Glass specular-
//  highlight animation (the same "white element grows and fades" artifact that
//  affected the default Toggle). Uses a matchedGeometryEffect sliding
//  indicator with a plain spring — no glow, no scale pop.
//
//  Usage:
//      GKSegmentedPicker(options: [(.a, "A"), (.b, "B")], selection: $binding)
//

import SwiftUI

struct GKSegmentedPicker<T: Hashable>: View {

    /// Each entry is (value, display label).
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let isSelected = selection == value
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                        selection = value
                    }
                } label: {
                    Text(label)
                        .font(GKFont.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(GKColor.accent.opacity(0.15))
                                    .matchedGeometryEffect(id: "seg-indicator", in: ns)
                            }
                        }
                        .foregroundStyle(isSelected ? GKColor.accent : GKColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(GKColor.textSecondary.opacity(0.12))
        )
    }
}
