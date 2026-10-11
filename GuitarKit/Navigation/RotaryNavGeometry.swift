//
//  RotaryNavGeometry.swift
//  GuitarKit — Navigation
//
//  The PURE geometry behind the rotary nav wheel, extracted from `RotaryNavBar` so
//  the "shortest-spin" math can be unit-tested without standing up a SwiftUI view.
//
//  THE MODEL (see `RotaryNavBar` for the visual picture): the tool list is repeated
//  `copies` times around a full circle, giving `slotCount = toolCount · copies`
//  SLOTS spaced `anglePerItem` apart. Slot 0 sits at the apex (−90° in screen
//  coordinates); slot k shows `tools[k % toolCount]`. A single accumulating
//  `rotation` (degrees) spins the whole wheel; because the same tool appears in
//  many slots, selecting it means spinning by the SHORTEST delta that brings ANY of
//  its slots to the apex — that's the wrap-around math this struct owns.
//

import Foundation

struct RotaryNavGeometry {

    /// How many distinct tools sit on the wheel.
    let toolCount: Int
    /// How many times the tool list repeats around the circle (for a smooth
    /// infinite spin).
    let copies: Int

    init(toolCount: Int, copies: Int) {
        self.toolCount = max(toolCount, 1)
        self.copies = max(copies, 1)
    }

    /// Total slots around the full circle (tools × copies).
    var slotCount: Int { toolCount * copies }

    /// Degrees between adjacent slots, sized so all the slots fill exactly 360°.
    var anglePerItem: Double { 360.0 / Double(slotCount) }

    /// The fixed angle of slot `k` BEFORE the wheel's rotation: slot 0 is at the
    /// apex (−90°), each subsequent slot one `anglePerItem` step further round.
    func slotAngle(_ k: Int) -> Double {
        -90.0 + Double(k) * anglePerItem
    }

    /// Wrap any angle difference into (−180, 180] so we always take the SHORTEST
    /// equivalent rotation — the heart of "shortest path + infinite wrap."
    func normalizeToShortest(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }

    /// From the current `rotation`, the rotation value (closest to it, so the spin
    /// is shortest) that brings some slot showing tool index `toolIndex` up to the
    /// apex. The slots showing that tool are `toolIndex, toolIndex + toolCount, …`.
    func nearestRotation(forToolIndex toolIndex: Int, from rotation: Double) -> Double {
        var best = rotation
        var bestDistance = Double.infinity
        var k = ((toolIndex % toolCount) + toolCount) % toolCount
        while k < slotCount {
            // Rotation that puts slot k at the apex: slotAngle(k) + r ≡ −90.
            let candidate = rotation + normalizeToShortest(-90 - slotAngle(k) - rotation)
            let distance = abs(candidate - rotation)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
            k += toolCount
        }
        return best
    }
}
