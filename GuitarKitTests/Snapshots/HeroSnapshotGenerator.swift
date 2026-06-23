//
//  HeroSnapshotGenerator.swift
//  GuitarKitTests
//
//  NOT a behavioral test — a developer tool. It renders the tuner hero in four
//  representative states into a single PNG so the design can be reviewed without
//  a device or live audio. Writes to <repo>/.snapshots/. Safe to keep: it only
//  produces an image and asserts the file was written.
//

import XCTest
import SwiftUI
@testable import GuitarKit

@MainActor
final class HeroSnapshotGenerator: XCTestCase {

    /// A silent stand-in so rendering never tries to buzz the (non-existent)
    /// Taptic Engine.
    private final class SilentHaptics: TuningHapticsProviding {
        func prepare() {}
        func inTune() {}
        func perfect() {}
        func stringLatched() {}
        func sessionCompleted() {}
    }

    /// A controllable clock for driving the hold-to-latch logic deterministically.
    private final class FakeClock {
        var t: TimeInterval = 0
        func now() -> TimeInterval { t }
    }

    private let calc = PitchCalculator()

    private func freq(_ pc: PitchClass, _ oct: Int, centsOff: Double = 0) -> Double {
        calc.frequency(of: Note(pitchClass: pc, octave: oct)) * pow(2.0, centsOff / 1200.0)
    }

    private func reading(_ hz: Double) -> PitchReading {
        PitchReading(frequency: hz, note: Note.from(midiNumber: 69), centOffset: 0, clarity: 1)
    }

    private func makeModel() -> (TuningSessionModel, FakeClock) {
        let clock = FakeClock()
        let model = TuningSessionModel(now: clock.now, haptics: SilentHaptics())
        return (model, clock)
    }

    func test_generateHeroStatesImage() throws {
        // STATE 1 — idle (nothing played yet).
        let (idle, _) = makeModel()

        // STATE 2 — low E ~18¢ flat.
        let (flat, _) = makeModel()
        flat.ingest(reading(freq(.e, 2, centsOff: -18)))

        // STATE 3 — A string +2¢ (in tune), one string already latched.
        let (tuned, tClock) = makeModel()
        // Latch the low E first so the headstock shows a green/checked peg.
        tClock.t = 0;   tuned.ingest(reading(freq(.e, 2)))
        tClock.t = 1.0; tuned.ingest(reading(freq(.e, 2)))
        tClock.t = 1.2; tuned.ingest(nil)
        // Now sit on A just barely sharp.
        tClock.t = 1.3; tuned.ingest(reading(freq(.a, 2, centsOff: 2)))

        // STATE 4 — fully complete (all six latched) → completion flourish.
        let (done, dClock) = makeModel()
        let notes: [(PitchClass, Int)] = [(.e, 2), (.a, 2), (.d, 3), (.g, 3), (.b, 3), (.e, 4)]
        for (i, n) in notes.enumerated() {
            let base = Double(i) * 2.0
            dClock.t = base;       done.ingest(reading(freq(n.0, n.1)))
            dClock.t = base + 1.0; done.ingest(reading(freq(n.0, n.1)))
            dClock.t = base + 1.5; done.ingest(nil)
        }

        let grid = HStack(alignment: .top, spacing: 16) {
            labeled("Idle", idle)
            labeled("18¢ flat", flat)
            labeled("In tune", tuned)
            labeled("Complete", done)
        }
        .padding(28)
        .background(GKColor.background)
        .environment(\.colorScheme, .dark)        // app is dark-first
        .frame(width: 1180, height: 540)

        let renderer = ImageRenderer(content: grid)
        renderer.scale = 2
        guard let image = renderer.uiImage, let png = image.pngData() else {
            return XCTFail("Failed to render hero snapshot")
        }

        // Resolve <repo>/.snapshots from THIS source file's location (#filePath),
        // so the output path isn't hardcoded to one machine/user. This file lives
        // at <repo>/GuitarKitTests/Snapshots/, so go up two directories.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Snapshots/
            .deletingLastPathComponent()      // GuitarKitTests/
            .deletingLastPathComponent()      // <repo>/
        let dir = repoRoot.appendingPathComponent(".snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("hero-states.png")
        try png.write(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    @ViewBuilder
    private func labeled(_ title: String, _ model: TuningSessionModel) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(GKFont.caption)
                .foregroundStyle(GKColor.textSecondary)
            TunerHeroView(model: model)
                .frame(width: 260, height: 440)
        }
    }
}
