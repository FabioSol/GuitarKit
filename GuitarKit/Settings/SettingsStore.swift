//
//  SettingsStore.swift
//  GuitarKit
//
//  The single home for GuitarKit's GLOBAL, PERSISTENT preferences — the settings
//  that should survive app launches and apply everywhere (reference pitch,
//  haptics on/off, theme, handedness, …). Per the PRD, per-tool *ephemeral*
//  choices stay inside their tool; only durable, app-wide prefs live here.
//
//  WHY ONE OBSERVABLE STORE (not scattered @AppStorage props)?
//  SwiftUI's `@AppStorage` works for a single screen, but our settings feed many
//  subsystems (the pitch calculator, the tuning session's haptics, the app's
//  color scheme). Centralising them in one `@Observable` object means:
//    • every screen reads/writes the SAME live values (change theme in Settings →
//      the whole app updates), and
//    • we can hand a throwaway `UserDefaults` to this object in tests and verify
//      persistence without touching the developer's real preferences.
//
//  HOW PERSISTENCE WORKS HERE:
//  Each setting is a normal stored property. Its `didSet` observer writes the new
//  value to `UserDefaults` under a stable string key. The initialiser does the
//  reverse — it reads every key back (falling back to a sensible default when the
//  key was never written). So the flow is: change property → didSet saves → next
//  launch's init loads. UserDefaults is iOS's small on-device key/value store;
//  it's exactly right for a handful of simple preferences (no database needed),
//  and it never leaves the device — which matters for our privacy promise.
//

import Foundation
import Observation

// MARK: - Setting choice enums
//
// We model the multiple-choice settings as `enum`s rather than raw strings/ints.
// An enum makes the *legal* options the only representable ones ("make illegal
// states unrepresentable"), gives us exhaustive `switch`es the compiler checks,
// and — by backing each enum with a `String` raw value — gives us a stable token
// to store in UserDefaults that won't break if we reorder the cases later.
//
// `CaseIterable` lets a `Picker` enumerate every option with `.allCases`.
// `Identifiable` (via `id: self`) lets SwiftUI use each case directly in a
// `ForEach`. `Codable`/`Sendable` are cheap, useful conformances for a value
// type that crosses persistence and concurrency boundaries.

/// How strict the "you're in tune" verdict is. This maps to a tolerance in
/// *cents* (1 cent = 1/100 of a semitone): a smaller window means the tuner only
/// says "in tune" when you're very close. The pure tuning logic ultimately
/// consumes a cents number; this enum is the friendly, user-facing knob.
enum InTuneSensitivity: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Forgiving — good for beginners or noisy rooms (a wider in-tune window).
    case relaxed
    /// The default balance most players want.
    case standard
    /// Demanding — for studio/precise work (a narrow in-tune window).
    case strict

    var id: Self { self }

    /// The half-width of the in-tune window, in cents. The tuner counts a note as
    /// "in tune" when its deviation from the target is within ± this many cents.
    /// These numbers are the bridge from this user-facing choice to the pure
    /// tuning math (the orchestrator can feed this into `TuningTolerance`).
    var centsTolerance: Double {
        switch self {
        case .relaxed:  return 8
        case .standard: return 5
        case .strict:   return 3
        }
    }

    /// A short label for the UI picker. Computed so the display text lives next to
    /// the case it describes (and stays in one language-localisable place later).
    var displayName: String {
        switch self {
        case .relaxed:  return "Relaxed"
        case .standard: return "Standard"
        case .strict:   return "Strict"
        }
    }
}

/// The little sound (if `soundEnabled`) played when a string locks in tune.
/// A short, named set keeps the choices curated; the actual audio assets are
/// wired by the Feedback/audio slice — this enum is just the persisted choice.
enum ConfirmationSound: String, CaseIterable, Identifiable, Codable, Sendable {
    case chime
    case ding
    case pluck

    var id: Self { self }

    var displayName: String {
        switch self {
        case .chime: return "Chime"
        case .ding:  return "Ding"
        case .pluck: return "Pluck"
        }
    }
}

/// Which appearance the app forces, or whether it follows the system. SwiftUI's
/// `.preferredColorScheme` takes an optional `ColorScheme`; `.system` maps to
/// `nil` (follow the device), the others to the matching scheme.
enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

/// The brand accent. v1 ships a single purple signature (PRD: "Single signature
/// for v1; curated theme picker later"). Modelling it as an enum with one case
/// now means we can add cases later without changing the setting's *type* or its
/// UserDefaults key — the persisted storage already speaks "accent tokens".
enum AppAccent: String, CaseIterable, Identifiable, Codable, Sendable {
    case purple

    var id: Self { self }

    var displayName: String {
        switch self {
        case .purple: return "Purple"
        }
    }
}

/// Left- or right-handed layout. Drives the global fretboard/headstock mirror
/// (PRD: "global handedness mirror"). Right-handed is the default.
enum Handedness: String, CaseIterable, Identifiable, Codable, Sendable {
    case right
    case left

    var id: Self { self }

    var displayName: String {
        switch self {
        case .right: return "Right-handed"
        case .left:  return "Left-handed"
        }
    }
}

/// Whether ambiguous black-key notes are spelled with sharps (C♯) or flats (D♭)
/// by default. This is the app-wide *default*; tools may still override locally.
enum NoteLabeling: String, CaseIterable, Identifiable, Codable, Sendable {
    case sharps
    case flats

    var id: Self { self }

    var displayName: String {
        switch self {
        case .sharps: return "Sharps (♯)"
        case .flats:  return "Flats (♭)"
        }
    }
}

// MARK: - The store

/// The app's global preferences, observable and UserDefaults-backed.
///
/// `@MainActor` — settings are read and written from the UI, which lives on the
/// main actor; pinning the whole class there keeps every access safe with no
/// locks. `@Observable` makes SwiftUI re-render exactly the views that read a
/// changed setting. `final` because we never subclass it (a small speed win and
/// a clear "this is the whole thing" signal).
@MainActor
@Observable
final class SettingsStore {

    // MARK: Storage keys
    //
    // Every persisted value gets a stable, namespaced key string, gathered here
    // so they live in ONE place (no stringly-typed typos scattered through the
    // didSets). `enum Key` is a pure namespace — see GKColor for the same trick.
    // IMPORTANT: never rename these once shipped, or users lose their saved
    // settings (the old key simply won't be found and the default kicks in).
    private enum Key {
        static let referencePitchHz   = "guitarkit.settings.referencePitchHz"
        static let sweetenedTuning     = "guitarkit.settings.sweetenedTuningEnabled"
        static let inTuneSensitivity   = "guitarkit.settings.inTuneSensitivity"
        static let hapticsEnabled      = "guitarkit.settings.hapticsEnabled"
        static let soundEnabled        = "guitarkit.settings.soundEnabled"
        static let confirmationSound   = "guitarkit.settings.confirmationSound"
        static let theme               = "guitarkit.settings.theme"
        static let accent              = "guitarkit.settings.accent"
        static let handedness          = "guitarkit.settings.handedness"
        static let defaultLabeling     = "guitarkit.settings.defaultLabeling"
        static let experimentalHeroViz = "guitarkit.settings.experimentalHeroVisualization"
        static let experimentalFingerNumbers = "guitarkit.settings.experimentalFingerNumberLabels"
        static let experimentalReactiveBackdrop = "guitarkit.settings.experimentalReactiveBackdrop"
    }

    // MARK: Sensible defaults
    //
    // Gathered as `static let`s so BOTH `init` (first launch / missing key) and
    // `reset()` use the exact same source of truth — there's no risk of the two
    // disagreeing about what "default" means.
    enum Default {
        static let referencePitchHz = ReferencePitch.standard.hertz // 440
        static let sweetenedTuningEnabled = false
        static let inTuneSensitivity: InTuneSensitivity = .standard
        static let hapticsEnabled = true
        // PRD: the app is "silent by default" — sound starts OFF.
        static let soundEnabled = false
        static let confirmationSound: ConfirmationSound = .chime
        static let theme: AppTheme = .system
        static let accent: AppAccent = .purple
        static let handedness: Handedness = .right
        static let defaultLabeling: NoteLabeling = .sharps
        static let experimentalHeroVisualization = false
        static let experimentalFingerNumberLabels = false
        static let experimentalReactiveBackdrop = false
    }

    // MARK: The defaults store (injected)

    /// Which `UserDefaults` to persist into. Production uses `.standard`; tests
    /// pass an isolated named suite so they never touch real preferences.
    ///
    /// `@ObservationIgnored` keeps this out of SwiftUI's change tracking — it's
    /// infrastructure, not a value any view should re-render on.
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Tuning settings

    /// The reference frequency for A4, in Hertz (concert pitch = 440). We store a
    /// plain `Double` (UserDefaults can't hold a `ReferencePitch` directly), but
    /// we route every WRITE through `ReferencePitch` so the value is *always*
    /// clamped to the legal 415…466 band — the UI can't shove in nonsense.
    var referencePitchHz: Double = Default.referencePitchHz {
        didSet {
            // Re-clamp defensively: even if a caller assigns a wild value, what we
            // store (and keep in memory) stays valid.
            let clamped = ReferencePitch(hertz: referencePitchHz).hertz
            if clamped != referencePitchHz {
                // Assigning here re-enters didSet once with the clamped value,
                // which then matches and persists below. (One extra pass; cheap.)
                referencePitchHz = clamped
                return
            }
            defaults.set(referencePitchHz, forKey: Key.referencePitchHz)
        }
    }

    /// Whether per-string "sweetened" tuning offsets are applied (a subtle tweak
    /// some players prefer). Lives under Advanced; off by default for v1.
    var sweetenedTuningEnabled: Bool = Default.sweetenedTuningEnabled {
        didSet { defaults.set(sweetenedTuningEnabled, forKey: Key.sweetenedTuning) }
    }

    /// How strict the in-tune verdict is. Stored by its raw string so the choice
    /// is stable across app versions even if we reorder the enum cases.
    var inTuneSensitivity: InTuneSensitivity = Default.inTuneSensitivity {
        didSet { defaults.set(inTuneSensitivity.rawValue, forKey: Key.inTuneSensitivity) }
    }

    // MARK: Feedback settings

    /// Whether the tuner buzzes the Taptic engine on milestones. ON by default —
    /// haptics are GuitarKit's primary non-visual feedback channel.
    var hapticsEnabled: Bool = Default.hapticsEnabled {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    /// Whether confirmation *sounds* play. OFF by default (PRD: silent by default
    /// — a tuner you point at a quiet guitar shouldn't make noise unprompted).
    var soundEnabled: Bool = Default.soundEnabled {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) }
    }

    /// Which confirmation sound plays (only audible when `soundEnabled`).
    var confirmationSound: ConfirmationSound = Default.confirmationSound {
        didSet { defaults.set(confirmationSound.rawValue, forKey: Key.confirmationSound) }
    }

    // MARK: Appearance settings

    /// Forced appearance, or follow-the-system. Feeds `.preferredColorScheme`.
    var theme: AppTheme = Default.theme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    /// The brand accent (single purple for v1; room to grow).
    var accent: AppAccent = Default.accent {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }

    // MARK: Instrument settings

    /// Global left/right-handed layout mirror.
    var handedness: Handedness = Default.handedness {
        didSet { defaults.set(handedness.rawValue, forKey: Key.handedness) }
    }

    /// Default sharp/flat spelling for ambiguous notes.
    var defaultLabeling: NoteLabeling = Default.defaultLabeling {
        didSet { defaults.set(defaultLabeling.rawValue, forKey: Key.defaultLabeling) }
    }

    // MARK: Advanced — experimental feature flags
    //
    // These toggle PRD "flagged experiment" features that are ship-conditional on
    // quality. Modelled as individual Bools (clearer in the UI and in UserDefaults
    // than packing a set). They're real user-facing toggles, so they compile in
    // all builds — but see the DEBUG-only dev flag further down for the kind that
    // must NOT ship.

    /// Alternative hero note-visualization variant (PRD: "hero visualization
    /// variants" in the feature-flag list). Off by default.
    var experimentalHeroVisualization: Bool = Default.experimentalHeroVisualization {
        didSet { defaults.set(experimentalHeroVisualization, forKey: Key.experimentalHeroViz) }
    }

    /// Show finger-number labels on the fretboard (PRD: behind a flag,
    /// ship-conditional on quality). Off by default.
    var experimentalFingerNumberLabels: Bool = Default.experimentalFingerNumberLabels {
        didSet { defaults.set(experimentalFingerNumberLabels, forKey: Key.experimentalFingerNumbers) }
    }

    /// The reactive ambient backdrop experiment (PRD: kept as a flagged
    /// experiment). Off by default.
    var experimentalReactiveBackdrop: Bool = Default.experimentalReactiveBackdrop {
        didSet { defaults.set(experimentalReactiveBackdrop, forKey: Key.experimentalReactiveBackdrop) }
    }

    #if DEBUG
    /// A DEVELOPER-ONLY flag for A/B-ing internals during development. Wrapped in
    /// `#if DEBUG` so the WHOLE property — storage, UI row, everything — is
    /// COMPILED OUT of release builds (PRD: "dev flags compiled out of release").
    /// It is intentionally NOT persisted to UserDefaults: a dev toggle should
    /// reset every launch rather than linger, and never appears in a shipped app.
    var debugShowDiagnosticsOverlay: Bool = false
    #endif

    // MARK: Init

    /// Build the store, loading every setting from `defaults` (or its default when
    /// the key was never written — i.e. a fresh install).
    ///
    /// - Parameter defaults: where to persist. Defaults to `.standard`.
    ///
    /// NOTE ON THE DEFAULT ARGUMENT: `UserDefaults.standard` is fine as a default
    /// argument here — it is *not* a main-actor-isolated expression (it's a plain
    /// Foundation singleton), so it doesn't trip the "main-actor default argument"
    /// warning this project is careful about. We keep it simple.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load each value. We DON'T just assign the property (that would fire the
        // didSet and write straight back — harmless but pointless), so we read via
        // small helpers that return the stored value or the default. Assigning the
        // result to the property still fires didSet once, re-persisting the loaded
        // (or default) value; for a first launch that conveniently *seeds* the
        // store with defaults, and on later launches it's a cheap idempotent write.

        // Reference pitch: stored as a Double. `object(forKey:)` is nil when the
        // key was never set, letting us tell "missing" from "explicitly 0".
        if let hz = defaults.object(forKey: Key.referencePitchHz) as? Double {
            referencePitchHz = hz
        } else {
            referencePitchHz = Default.referencePitchHz
        }

        sweetenedTuningEnabled = Self.loadBool(
            from: defaults, key: Key.sweetenedTuning, default: Default.sweetenedTuningEnabled)

        inTuneSensitivity = Self.loadEnum(
            from: defaults, key: Key.inTuneSensitivity, default: Default.inTuneSensitivity)

        hapticsEnabled = Self.loadBool(
            from: defaults, key: Key.hapticsEnabled, default: Default.hapticsEnabled)

        soundEnabled = Self.loadBool(
            from: defaults, key: Key.soundEnabled, default: Default.soundEnabled)

        confirmationSound = Self.loadEnum(
            from: defaults, key: Key.confirmationSound, default: Default.confirmationSound)

        theme = Self.loadEnum(
            from: defaults, key: Key.theme, default: Default.theme)

        accent = Self.loadEnum(
            from: defaults, key: Key.accent, default: Default.accent)

        handedness = Self.loadEnum(
            from: defaults, key: Key.handedness, default: Default.handedness)

        defaultLabeling = Self.loadEnum(
            from: defaults, key: Key.defaultLabeling, default: Default.defaultLabeling)

        experimentalHeroVisualization = Self.loadBool(
            from: defaults, key: Key.experimentalHeroViz,
            default: Default.experimentalHeroVisualization)

        experimentalFingerNumberLabels = Self.loadBool(
            from: defaults, key: Key.experimentalFingerNumbers,
            default: Default.experimentalFingerNumberLabels)

        experimentalReactiveBackdrop = Self.loadBool(
            from: defaults, key: Key.experimentalReactiveBackdrop,
            default: Default.experimentalReactiveBackdrop)
    }

    // MARK: Reset

    /// Restore every setting to its factory default. Because each assignment fires
    /// its `didSet`, this also rewrites UserDefaults — so a reset persists, exactly
    /// like the user had set each control back by hand.
    func reset() {
        referencePitchHz = Default.referencePitchHz
        sweetenedTuningEnabled = Default.sweetenedTuningEnabled
        inTuneSensitivity = Default.inTuneSensitivity
        hapticsEnabled = Default.hapticsEnabled
        soundEnabled = Default.soundEnabled
        confirmationSound = Default.confirmationSound
        theme = Default.theme
        accent = Default.accent
        handedness = Default.handedness
        defaultLabeling = Default.defaultLabeling
        experimentalHeroVisualization = Default.experimentalHeroVisualization
        experimentalFingerNumberLabels = Default.experimentalFingerNumberLabels
        experimentalReactiveBackdrop = Default.experimentalReactiveBackdrop
        #if DEBUG
        debugShowDiagnosticsOverlay = false
        #endif
    }

    // MARK: Load helpers
    //
    // Tiny `static` helpers so the init reads cleanly. `static` (not instance)
    // methods because they run mid-init, before `self` is fully formed — they only
    // need the `defaults` passed in, not `self`.

    /// Read a `Bool` for `key`, returning `default` if the key was never written.
    /// We can't use `defaults.bool(forKey:)` directly because it returns `false`
    /// for a missing key — which would wrongly override a `true` default (like
    /// `hapticsEnabled`). Checking `object(forKey:)` for nil distinguishes
    /// "never set" from "explicitly false".
    private static func loadBool(
        from defaults: UserDefaults, key: String, default fallback: Bool
    ) -> Bool {
        guard let value = defaults.object(forKey: key) as? Bool else { return fallback }
        return value
    }

    /// Read a `RawRepresentable` enum (backed by `String`) for `key`, returning
    /// `default` if the key is missing OR holds an unrecognised raw value (e.g. a
    /// case removed in a later version). The generic `T` keeps one helper serving
    /// every enum setting instead of copy-pasting per type.
    private static func loadEnum<T: RawRepresentable>(
        from defaults: UserDefaults, key: String, default fallback: T
    ) -> T where T.RawValue == String {
        guard
            let raw = defaults.string(forKey: key),
            let value = T(rawValue: raw)
        else { return fallback }
        return value
    }
}
