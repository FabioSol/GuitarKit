//
//  HeadstockLayout.swift
//  GuitarKit
//
//  Where each string's tuning peg sits on the headstock, so the highlighted peg
//  on screen maps to the real peg the player's hand reaches for (PRD story 10).
//
//  Positions are NORMALIZED (0...1) within the headstock's drawing area, so the
//  same layout scales to any size. (0,0) is top-left, (1,1) bottom-right.
//
//  ⚠️ PLACEHOLDER SCOPE: only standard 6-string guitar (3 pegs per side) lives
//  here. The Instruments/Presets slice (#09) generalizes this — each instrument
//  entry carries its own peg/headstock layout (banjo's 5th peg, violin's 2+2
//  pegbox, 7/8-string, basses). This file is the seam that #09 grows into.
//

import CoreGraphics

/// One peg's normalized position on the headstock.
struct PegPosition: Equatable {
    /// 0 (left edge) … 1 (right edge).
    let x: CGFloat
    /// 0 (top edge) … 1 (bottom edge).
    let y: CGFloat
}

/// The peg arrangement for an instrument's headstock. `pegs[i]` is the position
/// of string `i` (same index order as the tuning's targets, low → high).
struct HeadstockLayout: Equatable {
    let pegs: [PegPosition]

    /// Standard 6-string guitar: a "3 + 3" headstock — three pegs down the left
    /// side, three down the right.
    ///
    /// MAPPING TO A REAL GUITAR (nut at the bottom, headstock pointing up):
    /// the eye traces the strings as a loop — the low E sits BOTTOM-LEFT (nearest
    /// the nut on the bass side), up the left side (A, D), then across the top and
    /// back DOWN the right side (G, B, high E), so the high E lands BOTTOM-RIGHT.
    // Peg x-columns (0.24 / 0.76) hug the tuner-post positions on the sides of
    // `HeadstockShape`; the three y-rows are evenly spaced down each side.
    static let standardGuitar = HeadstockLayout(pegs: [
        PegPosition(x: 0.24, y: 0.67),   // 0 low E  — left, bottom
        PegPosition(x: 0.24, y: 0.46),   // 1 A      — left, middle
        PegPosition(x: 0.24, y: 0.25),   // 2 D      — left, top
        PegPosition(x: 0.76, y: 0.25),   // 3 G      — right, top
        PegPosition(x: 0.76, y: 0.46),   // 4 B      — right, middle
        PegPosition(x: 0.76, y: 0.67)    // 5 high E — right, bottom
    ])

    /// Best-effort layout for an arbitrary string count, so the hero still draws
    /// something sensible if a non-standard tuning sneaks in before #09. Splits
    /// the strings into two evenly-spaced columns (left half low, right half
    /// high), mirroring the guitar arrangement.
    static func generic(stringCount: Int) -> HeadstockLayout {
        guard stringCount > 0 else { return HeadstockLayout(pegs: []) }
        let perSide = Int(ceil(Double(stringCount) / 2.0))

        // Evenly spaced y positions for `n` pegs down one side (inset from edges).
        func columnYs(_ n: Int) -> [CGFloat] {
            guard n > 1 else { return [0.5] }
            return (0..<n).map { 0.2 + (0.6 * CGFloat($0) / CGFloat(n - 1)) }
        }

        let leftYs = columnYs(perSide)
        let rightYs = columnYs(stringCount - perSide)

        var pegs: [PegPosition] = []
        // Left column top→bottom for the low strings…
        for i in 0..<perSide {
            pegs.append(PegPosition(x: 0.24, y: leftYs[i]))
        }
        // …then right column bottom→top for the high strings.
        for y in rightYs.reversed() {
            pegs.append(PegPosition(x: 0.76, y: y))
        }
        return HeadstockLayout(pegs: pegs)
    }
}
