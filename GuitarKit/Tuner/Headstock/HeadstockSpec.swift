//
//  HeadstockSpec.swift
//  GuitarKit
//
//  The DESIGNER-FACING description of a headstock, decoupled from code so the
//  look of each instrument's head can be authored without recompiling.
//
//  THE PIPELINE (the decoupling you asked for):
//    1. A designer draws the head silhouette and exports it as an SVG.
//    2. The SVG is dropped into the asset catalog (Assets.xcassets) — Xcode
//       imports SVGs as scalable vectors, so `Image("name")` renders it crisply
//       at any size.
//    3. A small JSON file (one per instrument, bundled under `Headstocks/`)
//       names that art asset, the head's aspect ratio, and the normalized
//       position of each tuning peg.
//    4. This `HeadstockSpec` decodes that JSON; `HeadstockView` renders the art
//       and overlays the LIVE peg dots (which must stay code-drawn so they can
//       change color per tuning state and be tapped).
//
//  Adding or restyling an instrument's head therefore means dropping in an SVG +
//  a JSON — no Swift changes. See `Headstocks/README.md` for the authoring guide.
//

import Foundation

/// A decoded headstock description: where the art comes from and where the pegs
/// sit. Pure `Codable` data — no view logic.
struct HeadstockSpec: Codable, Equatable {

    /// The asset-catalog image name for the silhouette (a designer's imported
    /// SVG). When `nil`, the app falls back to its built-in procedural shape —
    /// so the tuner works before any bespoke art exists.
    var artAsset: String?

    /// width ÷ height of the head's drawing area, so the layout reserves the
    /// right shape regardless of screen size.
    var aspectRatio: Double

    /// Peg anchor positions in string order (low → high), each normalized to the
    /// head's bounding box (0 = left/top, 1 = right/bottom). These MUST line up
    /// with the tuner posts in the SVG art.
    var pegs: [PegPosition]

    /// The nut ("bone") position + width. Optional — instruments that don't author
    /// one fall back to `NutSpec.default` (a centred bar). Authored per instrument
    /// so the bar and the string fan sit on the real neck, even when it's offset
    /// (the asymmetric bass) or narrow (the violin pegbox).
    var nut: NutSpec?

    /// The resolved nut, applying the default when none was authored.
    var resolvedNut: NutSpec { nut ?? .default }

    /// Whether to draw the fanned string lines. Optional; defaults to `true`. The
    /// violin turns this off — its strings are hidden inside the pegbox, so drawn
    /// lines would just be clutter (there's nowhere on the side-mounted pegs for a
    /// string to visibly run to).
    var showStrings: Bool?
}

// MARK: - Loading

extension HeadstockSpec {

    /// Decode a bundled spec JSON by file name (without extension), e.g.
    /// `HeadstockSpec.load("guitar")`. Looks under the `Headstocks/` resource
    /// folder first, then the bundle root. Returns `nil` if missing/invalid so
    /// callers can fall back gracefully.
    static func load(_ name: String, in bundle: Bundle = .main) -> HeadstockSpec? {
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Headstocks")
            ?? bundle.url(forResource: name, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HeadstockSpec.self, from: data)
    }

    /// The standard six-string guitar head. Prefers the bundled JSON; if that's
    /// somehow unavailable, falls back to the built-in procedural layout so the
    /// tuner never renders an empty head.
    static var standardGuitar: HeadstockSpec {
        load("guitar") ?? HeadstockSpec(
            artAsset: nil,
            aspectRatio: 0.66,
            pegs: HeadstockLayout.standardGuitar.pegs
        )
    }
}
