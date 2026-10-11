//
//  main.swift — PitchBench command-line runner
//
//  Built by `PitchBench/run.sh` together with the app's pitch sources and the
//  benchmark code from GuitarKitTests, with optimizations on. Same code as
//  `PitchBenchmarkTests`, minus the simulator and minus Debug-build slowness.
//
//    run.sh          → run every clip with every engine, write PitchBench/RESULTS*.md
//    run.sh serve    → parameter-search server for `tune.py` (see below)
//

import Foundation

// MARK: - serve

/// One request per stdin line:
///   {"params": {...TunableParams...}, "splits": ["train"], "byBackground": false, "byPluck": false}
/// One JSON reply per line on stdout:
///   {"train": {...BenchScore...}, "byBackground": {"train": {"speech @ -40 dB": {...}}}}
///
/// Splits: `train` and `test` are the generated clips with DIFFERENT random
/// details (seed bases 1 and 2); `recorded` is PitchBench/recordings/; `tones`
/// is clean sines + harmonic tones (a precision/robustness guard). They're
/// built once at startup, so each request only pays for the replay.
struct Request: Decodable {
    var params = TunableParams()
    var splits = ["train"]
    var byBackground = false
    var byPluck = false

    enum CodingKeys: String, CodingKey { case params, splits, byBackground, byPluck }

    // Every key is optional: a missing one keeps the default above.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        params = try c.decodeIfPresent(TunableParams.self, forKey: .params) ?? params
        splits = try c.decodeIfPresent([String].self, forKey: .splits) ?? splits
        byBackground = try c.decodeIfPresent(Bool.self, forKey: .byBackground) ?? byBackground
        byPluck = try c.decodeIfPresent(Bool.self, forKey: .byPluck) ?? byPluck
    }
}

struct Reply: Encodable {
    var scores: [String: BenchScore] = [:]
    var byBackground: [String: [String: BenchScore]]?
    var byPluck: [String: [String: BenchScore]]?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (split, score) in scores { try c.encode(score, forKey: AnyKey(split)) }
        if let byBackground { try c.encode(byBackground, forKey: AnyKey("byBackground")) }
        if let byPluck { try c.encode(byPluck, forKey: AnyKey("byPluck")) }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

func serve() throws {
    let splits: [String: [BenchClip]] = [
        "train": PitchBenchmark.syntheticClips(seedBase: 1),
        "test": PitchBenchmark.syntheticClips(seedBase: 2),
        "recorded": try PitchBenchmark.loadRecordings(),
        "tones": PitchBenchmark.cleanTones(),
    ]
    let counts = splits.map { "\($0.key)=\($0.value.count)" }.sorted().joined(separator: " ")
    FileHandle.standardError.write("ready \(counts)\n".data(using: .utf8)!)
    print("{\"ready\":true}")
    fflush(stdout)

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    while let line = readLine() {
        guard !line.isEmpty else { continue }
        var reply = Reply()
        do {
            let request = try decoder.decode(Request.self, from: Data(line.utf8))
            if request.byBackground { reply.byBackground = [:] }
            if request.byPluck { reply.byPluck = [:] }
            for name in request.splits {
                let results = (splits[name] ?? []).map { PitchBenchmark.run($0, params: request.params) }
                reply.scores[name] = PitchBenchmark.score(results)
                if request.byBackground {
                    reply.byBackground?[name] = Dictionary(grouping: results, by: \.clip.background)
                        .mapValues(PitchBenchmark.score)
                }
                if request.byPluck {
                    // Plucked clips only, grouped by strength.
                    reply.byPluck?[name] = Dictionary(grouping: results.filter { $0.clip.pluck != nil },
                                                      by: { $0.clip.pluck! })
                        .mapValues(PitchBenchmark.score)
                }
            }
            print(String(decoding: try encoder.encode(reply), as: UTF8.self))
        } catch {
            print("{\"error\":\"\(error)\"}")
        }
        fflush(stdout)
    }
}

// MARK: - main

do {
    if CommandLine.arguments.dropFirst().first == "serve" {
        try serve()
    } else {
        // Every engine gets its own report: RESULTS.md (the app default) and
        // RESULTS-<engine>.md for the others.
        for engine in PitchEngine.allCases {
            let report = try PitchBenchmark.writeResults(engine: engine)
            if engine == PitchTrackerConfig().engine {
                // Print the default engine's summary; the rest are in the files.
                print(report.components(separatedBy: "<details>").first ?? report)
            }
        }
        print("Wrote RESULTS.md and RESULTS-*.md in \(PitchBenchmark.benchDirectory.path)")
    }
} catch {
    print("PitchBench failed: \(error)")
    exit(1)
}
