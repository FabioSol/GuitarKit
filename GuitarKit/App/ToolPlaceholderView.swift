//
//  ToolPlaceholderView.swift
//  GuitarKit
//
//  A single placeholder screen used for all five tools in this foundation
//  slice. Each real tool (Tuner, Metronome, …) will replace this with its own
//  view in later slices; for now they all share this stub so we can build and
//  test the app shell + navigation end to end.
//

import SwiftUI

/// A `struct` conforming to `View` is the fundamental building block of
/// SwiftUI: a small, value-type description of a piece of UI. SwiftUI reads
/// the `body` to know what to draw.
struct ToolPlaceholderView: View {

    /// Which tool this placeholder is standing in for. Passed in by the shell.
    /// A stored `let` property = immutable input to the view.
    let tool: GKTool

    var body: some View {
        // `ZStack` layers its children back-to-front. We put the background
        // gradient at the back and the centered content in front.
        ZStack {
            // The shared ambient backdrop (a subtle gradient). Solid content,
            // not glass — this is the canvas the glass chrome floats over.
            backdrop

            // The centered "this tool is coming" content.
            VStack(spacing: 16) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 64, weight: .light))
                    // Tint the icon with our brand accent.
                    .foregroundStyle(GKColor.accent)

                Text(tool.title)
                    .font(GKFont.largeTitle)
                    .foregroundStyle(GKColor.textPrimary)

                Text("Coming soon")
                    .font(GKFont.caption)
                    .foregroundStyle(GKColor.textSecondary)
            }
            .padding()
        }
        // Let the backdrop run under the safe areas (edge to edge) so the
        // gradient fills the whole screen behind the nav.
        .ignoresSafeArea()
        // Expose the screen's purpose to VoiceOver as a single grouped element
        // with a clear label.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.title) screen")
    }

    /// The subtle, static ambient gradient described in the PRD. Pulled into
    /// its own computed property to keep `body` readable.
    private var backdrop: some View {
        // A diagonal gradient from a faint accent-tinted top to the base
        // background. Kept very low-contrast so it reads as "ambient," not
        // "loud."
        LinearGradient(
            colors: [
                GKColor.accent.opacity(0.18),
                GKColor.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// `#Preview` renders this view live in Xcode's canvas without launching the
// app. Great for iterating on a single screen.
#Preview {
    ToolPlaceholderView(tool: .tuner)
}
