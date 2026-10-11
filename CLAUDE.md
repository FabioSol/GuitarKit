# GuitarKit

iOS 26.5, iPhone-only, SwiftUI. Fabio's first Swift project.

## Where things are

- Product vision and every design decision so far: `docs/PRD.md`, `issues/`. Architecture decisions: `docs/adr/`.
- Domain words (target, latch, reading, selection…): `CONTEXT.md` — use these names in code and conversation.
- Pitch-detection quality: `PitchBench/README.md` — read it before touching anything in `GuitarKit/Domain/Pitch/`.
- Last codebase audit (findings may be fixed since): `audit/README.md`.

## Building and testing

`xcode-select` points at the Command Line Tools, so prefix Xcode commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Scheme `GuitarKit`; simulators are "iPhone 17 Pro" etc.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme GuitarKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
PitchBench/run.sh                                   # pitch benchmark → PitchBench/RESULTS*.md (~30 s, no simulator)
uv run --with optuna PitchBench/tune.py --help      # parameter search
```

Stopping an in-flight `xcodebuild test` can wedge the simulator (test host frozen at launch); `xcrun simctl shutdown all` or a Mac reboot clears it. The project uses file-system-synchronized groups: new files under `GuitarKit/` and `GuitarKitTests/` join their target automatically.

## Architecture rules

- **Default actor isolation is MainActor.** Pure domain types meant to run off the main thread (everything in `Domain/Pitch`, `Domain/Music`, `AudioLevel`) are declared `nonisolated`; keep new types there `nonisolated` too, or pitch detection can't run on its background queue.
- **Domain is pure.** `GuitarKit/Domain/` holds value types with no SwiftUI or AVFoundation (Accelerate is fine) — testable with plain inputs.
- **Single writers.** The instrument/tuning selection changes only through `TunerCoordinator.select` / `saveCustomTuning`. The audio session is configured only by `AudioSessionCoordinator` — each audio user holds `AudioSessionCoordinator.shared.client()` and states its need (ADR 0003).
- **Shell-owned models.** `RootView` rebuilds tool screens on every tool switch, so anything with state that must survive (view models, `TunerCoordinator`) is owned by `RootView` and passed in.
- **Detection numbers come from the benchmark.** Thresholds and model parameters in `Domain/Pitch` are measured choices (ADR 0004): change them with `PitchBench/` evidence, and quote the before/after.

## Comments

Fabio is learning Swift: comments explain the *why* and teach the Swift concept at hand (what `@Observable` does, why a `struct`), in plain language. Describe the code as it is now; history belongs in git and `docs/adr/`.
