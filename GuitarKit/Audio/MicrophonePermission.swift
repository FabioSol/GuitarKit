//
//  MicrophonePermission.swift
//  GuitarKit
//
//  Everything about asking for, and reading, microphone permission — wrapped so
//  the rest of the app deals in a small, friendly 3-case model instead of
//  Apple's raw enum.
//
//  THE MODERN API (iOS 17+):
//  Microphone permission used to live on `AVAudioSession` (and was deprecated).
//  The current home is `AVAudioApplication`:
//    • `AVAudioApplication.shared.recordPermission` → current state
//      (an `AVAudioApplication.recordPermission`: `.undetermined`/`.granted`/`.denied`)
//    • `AVAudioApplication.requestRecordPermission(completionHandler:)` →
//      shows the OS prompt the FIRST time and reports the user's choice.
//  We isolate both behind this file so if Apple moves the API again, only here
//  changes.
//

import AVFoundation
import Observation

// MARK: - Our own permission-state model

/// GuitarKit's view of microphone permission, in plain language. We map Apple's
/// `AVAudioApplication.recordPermission` onto these three cases so our UI code
/// reads clearly and so the mapping itself is pure and unit-testable (no audio
/// hardware required to verify it).
enum MicPermissionState: Equatable {
    /// The user hasn't been asked yet. This is the only state in which
    /// requesting permission will actually show the OS prompt.
    case undetermined
    /// The user granted mic access — we may start capturing audio.
    case granted
    /// The user denied (or revoked) access. Recoverable only via Settings, so
    /// our UI shows a deep-link there rather than re-prompting (a second
    /// `requestRecordPermission` when denied does nothing).
    case denied

    /// Translate Apple's raw enum into ours.
    ///
    /// WHY A SEPARATE MAPPING (and why `static`)?
    /// Keeping this conversion as a tiny pure function means we can unit-test the
    /// full truth table (`.granted → .granted`, etc.) without touching a real
    /// `AVAudioApplication`. It also gives us one obvious seam should Apple add a
    /// case in the future — `@unknown default` below forces us to consider it.
    static func from(_ apple: AVAudioApplication.recordPermission) -> MicPermissionState {
        switch apple {
        case .undetermined: return .undetermined
        case .granted:      return .granted
        case .denied:       return .denied
        // `@unknown default` is required because `recordPermission` is an
        // Objective-C enum Apple could extend in a future OS. Treating any
        // unknown future case as `.denied` is the safe, non-crashing fallback
        // (we'd rather show the recoverable Settings path than assume access).
        @unknown default:   return .denied
        }
    }
}

// MARK: - The permission manager (observable, app-facing)

/// A small observable object that owns the current `MicPermissionState` and
/// knows how to request permission. Views observe `state` and react.
///
/// `@MainActor` because it publishes UI-driving state and is touched from
/// SwiftUI; `@Observable` (the modern replacement for `ObservableObject`) makes
/// SwiftUI views automatically re-render when `state` changes — no
/// `@Published`, no `objectWillChange` boilerplate.
@MainActor
@Observable
final class MicrophonePermission {

    /// The current permission state, kept in sync with the system. Views read
    /// this to decide what to show (priming, meter, or the denied/Settings view).
    private(set) var state: MicPermissionState

    /// On creation we read the *current* system value so launches after the
    /// first reflect a previous grant/denial immediately (no flash of the
    /// priming screen for returning users who already granted).
    init() {
        self.state = MicPermissionState.from(
            AVAudioApplication.shared.recordPermission
        )
    }

    /// Re-read the system permission into `state`. Useful when returning from
    /// the Settings app (the user may have flipped the toggle while we were
    /// backgrounded), or any time we want to be certain we're current.
    func refresh() {
        state = MicPermissionState.from(
            AVAudioApplication.shared.recordPermission
        )
    }

    /// Ask the system for microphone permission.
    ///
    /// Behavior depends on the current OS-level state:
    ///   • `.undetermined` → shows the OS prompt; the user's choice updates `state`.
    ///   • `.granted`/`.denied` → no prompt; the completion fires with the
    ///     existing decision (so calling this is always safe).
    ///
    /// ASYNC BRIDGE:
    /// Apple's API is *callback-based* (`requestRecordPermission(completionHandler:)`).
    /// We wrap it in Swift's modern `async/await` using
    /// `withCheckedContinuation`, which turns "call me back later" into "await a
    /// value." That lets callers write a clean `await request()` instead of
    /// nesting closures. The callback may arrive on a background thread, so we
    /// hop back to the main actor (`await MainActor.run`) before touching `state`.
    func request() async {
        let granted: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { didGrant in
                // `didGrant` is `true`/`false`. Resume the awaiting caller with it.
                continuation.resume(returning: didGrant)
            }
        }

        // Reflect the result. We map straight from the Bool here rather than
        // re-reading the system, because the result is authoritative and avoids
        // a tiny race where the system value hasn't settled yet.
        state = granted ? .granted : .denied
    }
}
