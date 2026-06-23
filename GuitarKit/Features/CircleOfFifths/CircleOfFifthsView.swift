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

    /// The feature's single source of truth. `@State` on a reference type holds
    /// ONE instance alive across `body` rebuilds — exactly what we need so the
    /// selection persists. We initialise it with a fresh view model (defaulting
    /// to C major).
    ///
    /// (`@State` is normally for value types, but the modern pattern for an
    /// `@Observable` class a view *owns* is precisely `@State var model = …`. The
    /// view owns the object's lifetime; `@Observable` handles change tracking.)
    @State private var viewModel = CircleOfFifthsViewModel()

    var body: some View {
        ZStack {
            // The same ambient backdrop the rest of the app uses. Solid content,
            // behind the glass chrome.
            backdrop

            // A scrollable column so the wheel + panel fit on small devices and
            // with large Dynamic Type sizes without clipping.
            ScrollView {
                VStack(spacing: 24) {
                    // Screen title.
                    Text(GKTool.circleOfFifths.title)
                        .font(GKFont.largeTitle)
                        .foregroundStyle(GKColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // THE WHEEL (selector). Given a generous square so the twelve
                    // seats and their labels have room.
                    CircleWheelView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)

                    // THE DETAILS PANEL.
                    KeyDetailsPanelView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                // Leave room at the bottom so the floating rotary nav doesn't
                // cover the last chord chips.
                .padding(.bottom, 120)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// The shared ambient gradient (same recipe as ToolPlaceholderView so the
    /// tool feels part of the same app).
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
    CircleOfFifthsView()
}
