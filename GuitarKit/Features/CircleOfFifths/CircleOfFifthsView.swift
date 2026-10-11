//
//  CircleOfFifthsView.swift
//  GuitarKit — Circle of Fifths feature
//
//  The top-level screen for the Circle-of-Fifths explorer (issue #18). It stacks
//  the interactive wheel (a selector) above the details panel (signature,
//  relative key, diatonic chords) and owns the view model that ties them
//  together.
//
//  STATE OWNERSHIP / PRESERVATION (PRD story 49):
//  This view OWNS the view model via `@State`. Because `RootView` keeps each
//  tool's screen identity stable, the same `CircleOfFifthsView` instance — and
//  therefore the same view-model instance — survives while the app is running, so
//  navigating away to another tool and back preserves the current selection. (If
//  a future shell tears the screen down, hoist this `@State` up into `RootView`
//  to keep the model alive there instead — see the report's note.)
//

import SwiftUI

struct CircleOfFifthsView: View {

    /// The feature's single source of truth. INJECTED by `RootView` (which owns
    /// it via `@State`) so the explorer's selection survives navigating away and
    /// back — including when a cross-link jumps to Chords/Scales and the user
    /// returns (slice #21, PRD story 49).
    let viewModel: CircleOfFifthsViewModel

    /// CROSS-LINKS (slice #21) that promote the circle from explorer to hub. The
    /// shell (`RootView`) supplies these: tapping a diatonic chip opens that chord
    /// in the Chords tool; "View scale" opens the key's scale in the Scales tool.
    /// They default to no-ops so the view still previews standalone.
    var onOpenChord: (Chord) -> Void = { _ in }
    var onOpenScale: (Scale) -> Void = { _ in }

    var body: some View {
        ZStack {
            // The same ambient backdrop the rest of the app uses. Solid content,
            // behind the glass chrome.
            backdrop

            VStack(spacing: 14) {
                // Screen title.
                Text(GKTool.circleOfFifths.title)
                    .font(GKFont.largeTitle)
                    .foregroundStyle(GKColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // THE WHEEL (selector). Given a generous square so the twelve
                // seats and their labels have room.
                CircleWheelView(viewModel: viewModel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 290)

                // THE DETAILS PANEL — now the hub's action surface: its chord
                // chips and "View scale" button drive the cross-links.
                KeyDetailsPanelView(
                    viewModel: viewModel,
                    onOpenChord: onOpenChord,
                    onOpenScale: onOpenScale
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// The shared ambient gradient — the same accent-tinted backdrop recipe the
    /// other tools use, so the screen feels part of the same app.
    private var backdrop: some View {
        LinearGradient(
            colors: [GKColor.accent.opacity(0.18), GKColor.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    CircleOfFifthsView(viewModel: CircleOfFifthsViewModel())
}
