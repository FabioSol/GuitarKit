#!/bin/bash
# Build and run the pitch benchmark as an optimized Mac command-line tool:
# the app's real pitch code + the benchmark from GuitarKitTests. ~30 s to
# build, ~10 s to run — vs minutes inside a Debug simulator test run.
#
#   PitchBench/run.sh           run every clip, write PitchBench/RESULTS.md
#   PitchBench/run.sh serve     parameter-search server (used by tune.py)
#   PitchBench/run.sh --build   just build; prints the binary's path
#
set -euo pipefail
cd "$(dirname "$0")/.."

# xcode-select may point at the Command Line Tools; prefer the full Xcode.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

BUILD_DIR="${TMPDIR:-/tmp}/pitchbench"
mkdir -p "$BUILD_DIR"

xcrun swiftc -O -swift-version 5 -default-isolation MainActor -D PITCH_BENCH_CLI \
  GuitarKit/Domain/Music/*.swift \
  GuitarKit/Domain/Pitch/*.swift \
  GuitarKit/Audio/AudioLevel.swift \
  GuitarKitTests/Pitch/SignalGenerators.swift \
  GuitarKitTests/Pitch/Benchmark/PitchBenchmark.swift \
  GuitarKitTests/Pitch/Benchmark/Interference.swift \
  PitchBench/cli/main.swift \
  -o "$BUILD_DIR/pitchbench"

if [ "${1:-}" = "--build" ]; then
  echo "$BUILD_DIR/pitchbench"
else
  "$BUILD_DIR/pitchbench" "$@"
fi
