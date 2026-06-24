//
//  TunerVisualization.swift
//  GuitarKit
//
//  ONE INTERFACE, SEVERAL LOOKS.
//
//  The tuner's "how flat / sharp am I?" feedback can be drawn in different ways —
//  a linear meter, a radial ring, (later) a needle or a strobe. They all take the
//  SAME two inputs: the signed cents deviation and the classified `TuningZone`.
//  Slice #07 exists to A/B those looks against each other before we commit to a
//  final one, so we put them behind a single, swappable interface.
//
//  WHY BOTH A PROTOCOL *AND* AN ENUM?
//   • The `TunerVisualization` PROTOCOL is the contract: "a visualization is a
//     SwiftUI `View` you can build from (cents, zone)." Conforming our concrete
//     views to it guarantees they really are interchangeable — the compiler
//     enforces the shared shape.
//   • The `TunerVisualizationKind` ENUM is the runtime CHOICE: a small, listable
//     set of options the (debug-only) dev panel flips between live. Its `view`
//     method is the single call site the hero uses, so switching the whole look
//     is a one-line change with nothing else to touch.
//

import SwiftUI

// MARK: - The shared contract

/// What every tuner visualization is: a `View` that can be built from a cents
/// deviation (+ sharp / − flat, or `nil` when there's no reading) and the
/// classified `TuningZone`. Conforming to this is what makes the concrete looks
/// provably interchangeable.
///
/// (We don't use this protocol as an *existential* — `TunerVisualizationKind`
/// below picks the concrete type at the call site — so it stays a lightweight
/// documentary contract rather than something we have to type-erase.)
protocol TunerVisualization: View {
    init(cents: Double?, zone: TuningZone?)
}

// MARK: - The runtime choice

/// The catalogue of visualizations the tuner can wear. `CaseIterable` lets the
/// dev panel build its picker from the cases automatically; the `String` raw
/// value + `Identifiable` make it trivial to drive a SwiftUI `Picker`/`List`.
///
/// To add a candidate look later (needle, strobe), you add a `case`, a `label`,
/// and a line in `view(cents:zone:)` — nothing else in the app changes.
enum TunerVisualizationKind: String, CaseIterable, Identifiable {
    /// The default: a horizontal slider with a centre "in tune" detent.
    case linear
    /// A circular gauge: the indicator sweeps left→top→right, centred at the top
    /// when in tune.
    case radial

    /// `Identifiable` conformance — the raw string is already unique per case.
    var id: String { rawValue }

    /// A human-readable name for the dev picker.
    var label: String {
        switch self {
        case .linear: return "Linear meter"
        case .radial: return "Radial ring"
        }
    }

    /// Build the concrete visualization for this kind.
    ///
    /// `@ViewBuilder` is what lets each `case` return a DIFFERENT concrete view
    /// type (`CentsMeterView` vs `RadialTunerView`) while the method's signature
    /// promises only "some View". That's the seam the hero renders through, so
    /// choosing a look is just choosing a `TunerVisualizationKind`.
    @ViewBuilder
    func view(cents: Double?, zone: TuningZone?) -> some View {
        switch self {
        case .linear:
            CentsMeterView(cents: cents, zone: zone)
        case .radial:
            RadialTunerView(cents: cents, zone: zone)
        }
    }
}
