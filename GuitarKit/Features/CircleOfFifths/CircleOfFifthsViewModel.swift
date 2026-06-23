//
//  CircleOfFifthsViewModel.swift
//  GuitarKit — Circle of Fifths feature
//
//  This is the *brain* of the Circle-of-Fifths explorer (PRD stories 44, 45, 48,
//  49 / issue #18). It holds the explorer's state — which key is selected, which
//  seat that key sits at on the wheel, what the wheel's rotation should be — and
//  the small amount of logic that turns a tap into a new selection.
//
//  WHY A SEPARATE "VIEW MODEL" AT ALL?
//  SwiftUI views are meant to be thin, declarative *descriptions* of UI that get
//  thrown away and rebuilt constantly. Anything that must *survive* across those
//  rebuilds (and across navigating away from the tool and back — PRD story 49)
//  has to live somewhere more permanent. That "somewhere" is this object. By
//  pulling the state + logic out of the view we also make it plain Swift we can
//  unit-test without spinning up any UI (see CircleOfFifthsViewModelTests).
//
//  WHY A `class` AND `@Observable` (not a `struct`)?
//  A SwiftUI view that *owns* a reference object via `@State` keeps the SAME
//  instance alive for the whole lifetime of that view — even as `body` is
//  re-evaluated. That persistence is exactly what story 49 ("preserve the
//  selection") needs. `@Observable` is iOS 17+'s macro that makes the class's
//  stored properties automatically tracked: when one changes, only the views
//  that actually read it re-render. (A `struct` value type couldn't carry the
//  no-op closure hooks cleanly, and wouldn't give us one shared instance.)
//

import Foundation
import Observation

/// The observable state + behaviour for the Circle-of-Fifths explorer.
///
/// `@Observable` (from the `Observation` module) is a macro: at compile time it
/// rewrites this class so SwiftUI is notified whenever a property a view reads
/// actually changes. We don't have to annotate individual properties with
/// `@Published` the way the older `ObservableObject` required.
@Observable
final class CircleOfFifthsViewModel {

    // MARK: - Selection state

    /// The currently selected key (major or minor). This is THE piece of state
    /// the whole tool revolves around. It starts on C major — a sensible, neutral
    /// "home" key with no sharps or flats, and the conventional top seat of a
    /// circle-of-fifths diagram.
    ///
    /// `private(set)` means: anyone can *read* `selectedKey`, but only this class
    /// can *change* it. Callers mutate it through `select(_:)` below, which keeps
    /// the derived state (rotation, seat index) consistent — you can't set the
    /// key without also updating the rotation.
    private(set) var selectedKey: Key = CircleOfFifths.majorKeys[0] // C major

    /// The wheel's current rotation, in degrees. The wheel is drawn at this
    /// rotation; selecting a key changes it so the chosen seat swings up to the
    /// top "home" position. We animate the *view* reading this value, not the
    /// value itself, so the model stays a plain data holder.
    ///
    /// Starts at 0: with C at seat 0 already drawn at the top, no rotation is
    /// needed for the initial C-major selection.
    private(set) var rotationDegrees: Double = 0

    // MARK: - No-op playback hooks (wired to the synth in slice #13)
    //
    // AUDIO IS DELIBERATELY OUT OF SCOPE FOR THIS SLICE.
    // The issue's acceptance criterion says selecting a key "plays its scale,"
    // but the audio/synthesis engine doesn't exist yet — it arrives in slice
    // #13. Rather than pull a whole AVFoundation audio engine into this slice
    // prematurely, we expose two *optional closures* that a later slice will set.
    // Right now they are `nil`, so calling them does nothing (a "no-op").
    //
    // WHY OPTIONAL CLOSURES (`((Scale) -> Void)?`)?
    // A closure is a function value we can store and call later. Making it
    // Optional lets the feature run perfectly well with no audio wired up: we
    // call it with `onPlayScale?(scale)` and the `?` simply skips the call when
    // it's `nil`. When slice #13 lands, it assigns real implementations to these
    // properties (e.g. `viewModel.onPlayScale = { synth.play($0) }`) and the
    // exact same selection code starts making sound — no other changes needed.

    /// Called when a key is selected, handed the key's scale to play. `nil` =
    /// no audio yet. Slice #13 will set this to a real synth call.
    var onPlayScale: ((Scale) -> Void)?

    /// Called when an individual diatonic chord is activated (a later cross-link
    /// / preview hook), handed the chord. `nil` = no audio yet. Also reserved for
    /// slice #13.
    var onPlayChord: ((Chord) -> Void)?

    // MARK: - Init

    /// A trivial initializer. We give it explicitly (rather than relying on the
    /// synthesized one) so it's obvious the type is constructed with no
    /// arguments and starts on C major.
    init() {}

    // MARK: - Selection logic

    /// Select a key (from tapping either ring) and update the wheel rotation so
    /// that key's seat swings to the top. Also fires the (currently no-op) scale
    /// playback hook.
    ///
    /// This is the single funnel for *all* selection: both the outer (major) and
    /// inner (minor) ring taps call it. Centralising it means the rotation maths
    /// and the playback hook can never get out of sync with the selection.
    func select(_ key: Key) {
        selectedKey = key
        rotationDegrees = rotationToHome(for: key)

        // Fire the no-op scale hook. `scale(for:)` builds the right scale for the
        // key's mode; `onPlayScale?(...)` calls the closure only if one is set.
        onPlayScale?(scale(for: key))
    }

    // MARK: - Derived values (pure functions of the selection)

    /// The seat index (0..<12) a key occupies on the wheel. Both rings share the
    /// same twelve seats — `majorKeys[i]` and `minorKeys[i]` sit on the same
    /// spoke — so we find the index in whichever ring matches the key's mode.
    ///
    /// We return 0 (C / the top seat) as a safe fallback if a key we don't
    /// recognise is passed; in practice every key here comes from
    /// `CircleOfFifths`, so a match is always found.
    func seatIndex(of key: Key) -> Int {
        let ring = key.mode == .major ? CircleOfFifths.majorKeys
                                      : CircleOfFifths.minorKeys
        return ring.firstIndex(of: key) ?? 0
    }

    /// The wheel rotation (in degrees) needed to bring a key's seat to the top.
    ///
    /// THE GEOMETRY:
    /// We lay the twelve seats out clockwise, with seat 0 (C) at the top (12
    /// o'clock). Each seat is `360 / 12 = 30°` further clockwise. So seat `i`
    /// naturally sits at `i * 30°` *clockwise from the top*. To bring seat `i`
    /// back UP to the top, we must rotate the whole wheel the *same amount
    /// anticlockwise* — i.e. by `-(i * 30)` degrees. (Negative = anticlockwise in
    /// SwiftUI's rotation convention, where positive angles go clockwise.)
    func rotationToHome(for key: Key) -> Double {
        let seat = seatIndex(of: key)
        let degreesPerSeat = 360.0 / Double(CircleOfFifths.count)
        return -(Double(seat) * degreesPerSeat)
    }

    /// The scale that represents a key, used for the (future) "play its scale"
    /// hook and conceptually for any scale display. Major keys → major scale;
    /// minor keys → natural minor (the same default `DiatonicTriads` uses, so the
    /// scale and the chords agree).
    func scale(for key: Key) -> Scale {
        let type: ScaleType = key.mode == .major ? .major : .naturalMinor
        return Scale(root: key.tonic.pitchClass, type: type)
    }

    // MARK: - Details-panel data (read by the view)

    /// The selected key's diatonic triads (I, ii, iii, …) — the chord chips the
    /// details panel shows. Delegates entirely to the already-tested harmony
    /// domain; the view model just exposes it under a convenient name.
    var diatonicChords: [DiatonicChord] {
        DiatonicTriads.triads(in: selectedKey)
    }

    /// The selected key's relative key (relative minor for a major selection,
    /// relative major for a minor selection). PRD story 44's "relative minor."
    var relativeKey: Key {
        selectedKey.relative
    }
}
