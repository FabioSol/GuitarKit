"""
Search the pitch tracker's parameters with Optuna.

    uv run --with optuna PitchBench/tune.py --trials 400 --jobs 6
    uv run --with optuna PitchBench/tune.py --space probabilistic --study hmm

How it works
------------
* `PitchBench/run.sh serve` is a long-running process that holds the benchmark
  clips in memory and scores a parameter set per request (JSON over
  stdin/stdout). We start one per worker so trials run in parallel.
* Optuna searches with THREE goals at once (multi-objective), all measured on
  the generated TRAIN clips:
      coverage   ↑  share of each audible note with a correct reading
      wrongRate  ↓  share of windows showing a wrong note
      falseRate  ↓  share of windows showing a note when nothing was plucked
  There's no single "best" — the result is a Pareto front: settings where no
  goal can improve without another getting worse.
* Guard rail: every trial must keep ≥ 85% coverage on CLEAN TONES (pure sines
  and harmonic tones). Without it the search happily picks an algorithm that
  can't hear a pure tone — the generated clips all have harmonics, so nothing
  else would punish it.
* Overfitting guard: the front is then re-scored on the TEST clips (same
  conditions, different random details) and on the real RECORDINGS, which the
  search never sees. Picks are ranked on TEST, never on train.
* Ranking rule: a pick must detect at least as well as today's defaults —
  overall AND on soft plucks — and pass the clean tones; among those, fewest
  wrong + false readings wins. (Without the detection rule, "show nothing"
  scores well: silence is never wrong. That's the opposite of what a tuner
  that already needs hard plucks wants.)

Output: PitchBench/TUNING-<study>.md (the report) and PitchBench/tuning/ (the
Optuna studies, resumable, and recommended-<study>.json). `--report-only` re-ranks an existing
study without searching.
"""

import argparse
import json
from concurrent.futures import ThreadPoolExecutor
import subprocess
import sys
import threading
from datetime import datetime
from pathlib import Path

import optuna

ROOT = Path(__file__).resolve().parent.parent
BENCH = ROOT / "PitchBench"
OUT = BENCH / "tuning"


# ---------------------------------------------------------------------------
# The Swift benchmark server
# ---------------------------------------------------------------------------

class Server:
    """One `pitchbench serve` process: send params, get scores back."""

    def __init__(self, binary: str):
        self.proc = subprocess.Popen(
            [binary, "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1)
        ready = json.loads(self.proc.stdout.readline())
        assert ready.get("ready"), ready

    def score(self, params: dict, splits, by_background=False, by_pluck=False) -> dict:
        request = {"params": params, "splits": list(splits),
                   "byBackground": by_background, "byPluck": by_pluck}
        self.proc.stdin.write(json.dumps(request) + "\n")
        self.proc.stdin.flush()
        reply = json.loads(self.proc.stdout.readline())
        if "error" in reply:
            raise RuntimeError(reply["error"])
        return reply

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=10)


_local = threading.local()
_servers: list[Server] = []
_lock = threading.Lock()


def server(binary: str) -> Server:
    """The calling thread's own server (Optuna runs n_jobs threads)."""
    if not hasattr(_local, "server"):
        _local.server = Server(binary)
        with _lock:
            _servers.append(_local.server)
    return _local.server


# ---------------------------------------------------------------------------
# The search space — every knob in TunableParams
# ---------------------------------------------------------------------------

def suggest(trial: optuna.Trial) -> dict:
    return {
        "algorithm": trial.suggest_categorical("algorithm", ["mpm", "yin", "hps", "ensemble"]),
        "clarityThreshold": trial.suggest_float("clarityThreshold", 0.2, 0.95),
        "levelGateDB": trial.suggest_float("levelGateDB", -85, -40),
        "smoothing": trial.suggest_float("smoothing", 0.05, 1.0),
        "preprocessingEnabled": trial.suggest_categorical("preprocessingEnabled", [True, False]),
        "smootherWindow": trial.suggest_int("smootherWindow", 1, 9, step=2),
        "sustainClarityFactor": trial.suggest_float("sustainClarityFactor", 0.3, 1.0),
        "sustainLevelReliefDB": trial.suggest_float("sustainLevelReliefDB", 0, 18),
        "dropoutFrames": trial.suggest_int("dropoutFrames", 1, 6),
        "continuityAgreementCents": trial.suggest_float("continuityAgreementCents", 20, 200),
        # Capped at 0.75: generated strings score ~0.93 harmonicity, real ones
        # ~0.86 with a long tail — a search on generated clips would push the
        # gate to ~0.9, which on real recordings throws away 99% of string frames.
        "harmonicGate": trial.suggest_float("harmonicGate", 0, 0.75),
        "harmonicSustainFactor": trial.suggest_float("harmonicSustainFactor", 0.3, 1.0),
        "harmonicCount": trial.suggest_int("harmonicCount", 4, 12),
        "flatMarginSemitones": trial.suggest_float("flatMarginSemitones", 1, 11),
        "sharpMarginSemitones": trial.suggest_float("sharpMarginSemitones", 1, 7),
        "harmonicHeadroom": trial.suggest_float("harmonicHeadroom", 1.5, 6),
    }


def suggest_probabilistic(trial: optuna.Trial) -> dict:
    """The probabilistic engine (StringStateTracker): transition and evidence
    knobs. The front end (algorithm, band) stays at today's defaults."""
    return {
        "engine": "probabilistic",
        "onsetRiseDB": trial.suggest_float("onsetRiseDB", 1, 10),
        "startProbability": trial.suggest_float("startProbability", 0.001, 0.1, log=True),
        "onsetStartProbability": trial.suggest_float("onsetStartProbability", 0.02, 0.8),
        "stopProbability": trial.suggest_float("stopProbability", 0.005, 0.2, log=True),
        "switchProbability": trial.suggest_float("switchProbability", 0.001, 0.1, log=True),
        "onsetSwitchProbability": trial.suggest_float("onsetSwitchProbability", 0.02, 0.8),
        "detuneCents": trial.suggest_float("detuneCents", 50, 400),
        "stabilityCents": trial.suggest_float("stabilityCents", 5, 60),
        "stabilityWeight": trial.suggest_float("stabilityWeight", 0, 1),
        "hmmClarityMidpoint": trial.suggest_float("hmmClarityMidpoint", 0.2, 0.8),
        # Capped at 0.72 — the 25th percentile of REAL string frames' harmonicity
        # (generated strings score ~0.93, so an uncapped search would learn the
        # generator and reject a quarter of real string frames).
        "hmmHarmonicityMidpoint": trial.suggest_float("hmmHarmonicityMidpoint", 0.4, 0.72),
        "hmmHarmonicitySlope": trial.suggest_float("hmmHarmonicitySlope", 2, 30),
        "hmmLevelMidpointDB": trial.suggest_float("hmmLevelMidpointDB", -90, -55),
        "missEvidence": trial.suggest_float("missEvidence", -4, 0),
        "salienceMidpoint": trial.suggest_float("salienceMidpoint", 0.3, 0.8),
        "presenceBias": trial.suggest_float("presenceBias", -6, 0),
        "showThreshold": trial.suggest_float("showThreshold", 0.3, 0.9),
    }


SPACES = {"gated": suggest, "probabilistic": suggest_probabilistic}

# Today's defaults, so the search starts from (and is compared with) them.
DEFAULTS = {
    "algorithm": "ensemble", "clarityThreshold": 0.45, "levelGateDB": -68.0,
    "smoothing": 0.4, "preprocessingEnabled": True, "smootherWindow": 5,
    "sustainClarityFactor": 0.65, "sustainLevelReliefDB": 6.0, "dropoutFrames": 2,
    "continuityAgreementCents": 100.0, "harmonicGate": 0.65, "harmonicSustainFactor": 0.6,
    "harmonicCount": 8, "flatMarginSemitones": 5.0,
    "sharpMarginSemitones": 3.0, "harmonicHeadroom": 3.0,
}

OBJECTIVES = ("coverage", "wrongRate", "falseRate")

# A trial must keep this much coverage on clean tones (the defaults score 92%;
# the first window of every note is held for confirmation, so 100% is impossible).
MIN_TONES_COVERAGE = 0.85


def balanced(score: dict) -> float:
    """One number for RANKING the Pareto front (not for searching): every
    goal is a 0…1 rate, so reward coverage and charge both kinds of wrong."""
    return score["coverage"] - score["wrongRate"] - score["falseRate"]


# ---------------------------------------------------------------------------
# Re-scoring and ranking
# ---------------------------------------------------------------------------

SPLITS = ("train", "test", "recorded", "tones")


def full_score(srv: Server, params: dict) -> dict:
    """Every split, plus the soft-pluck slice of TEST."""
    scores = srv.score(params, SPLITS)
    scores["soft"] = srv.score(params, ["test"], by_pluck=True)["byPluck"]["test"]["soft"]
    return scores


def eligible(s: dict, d: dict) -> bool:
    """No worse than the defaults at FINDING notes, and hears clean tones."""
    slack = 0.01
    return (s["test"]["detectionRate"] >= d["test"]["detectionRate"] - slack
            and s["soft"]["detectionRate"] >= d["soft"]["detectionRate"] - slack
            and s["test"]["coverage"] >= d["test"]["coverage"] - slack
            and s["tones"]["coverage"] >= MIN_TONES_COVERAGE)


def rank(scored: list, defaults: dict) -> tuple[list, bool]:
    """Eligible picks by fewest wrong + false readings on TEST. Falls back to
    the balanced score if nothing qualifies (and says so)."""
    ok = [ts for ts in scored if eligible(ts[1], defaults)]
    if ok:
        ok.sort(key=lambda ts: (ts[1]["test"]["wrongRate"] + ts[1]["test"]["falseRate"],
                                -ts[1]["test"]["coverage"]))
        return ok, True
    return sorted(scored, key=lambda ts: balanced(ts[1]["test"]), reverse=True), False


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def pct(x: float) -> str:
    return f"{x * 100:.0f}%"


def row(name: str, s: dict) -> str:
    t = s["test"]
    return (f"| {name} | {pct(t['coverage'])} | {pct(t['wrongRate'])} | {pct(t['falseRate'])} | "
            f"{pct(t['detectionRate'])} | {pct(s['soft']['detectionRate'])} / {pct(s['soft']['coverage'])} | "
            f"{pct(s['tones']['coverage'])} | {pct(s['recorded']['coverage'])} / {pct(s['recorded']['wrongRate'])} | "
            f"{t['jitterCents']:.1f}¢ |")


HEADER = ("| config | coverage ↑ | wrong ↓ | false ↓ | detected ↑ | soft plucks: detected / coverage ↑ "
          "| clean tones ↑ | recorded: coverage ↑ / wrong ↓ | jitter ↓ |\n"
          "|---|---:|---:|---:|---:|---:|---:|---:|---:|")


def write_report(study, ranked, qualified, defaults, by_bg_default, by_bg_best, best, space="gated"):
    md = ["# Pitch tracker parameter search", ""]
    md.append(f"Generated by `PitchBench/tune.py` on {datetime.now():%Y-%m-%d %H:%M} — "
              f"{len(study.trials)} trials, {len(study.best_trials)} on the Pareto front.")
    md.append("")
    md.append("**Searched** on the generated TRAIN clips. **Scored** below on the generated TEST "
              "clips (same conditions, different random details) and your real **recorded** "
              "clips — the search saw neither. *Clean tones* = coverage on pure sines + harmonic "
              f"tones (must stay ≥ {pct(MIN_TONES_COVERAGE)}).")
    md.append("")
    md.append("**Ranking rule:** a pick must detect at least as well as today's defaults (overall "
              "and on soft plucks), keep coverage, and pass the clean tones; among those, fewest "
              "wrong + false readings wins.")
    md.append("")
    if not qualified:
        md.append("> ⚠️ No trial met the ranking rule — picks below are ranked by "
                  "coverage − wrong − false instead. Treat them with suspicion.")
        md.append("")
    md.append(HEADER)
    md.append(row("**today's defaults**", defaults))
    for i, (trial, s) in enumerate(ranked[:5], 1):
        md.append(row(f"pick #{i} (trial {trial.number})", s))
    md.append("")

    md.append("## Pick #1 vs defaults, per background (test clips)")
    md.append("")
    md.append("| background | coverage | wrong | false |")
    md.append("|---|---:|---:|---:|")
    for bg, d in by_bg_default.items():
        b = by_bg_best.get(bg, d)
        md.append(f"| {bg} | {pct(d['coverage'])} → **{pct(b['coverage'])}** | "
                  f"{pct(d['wrongRate'])} → **{pct(b['wrongRate'])}** | "
                  f"{pct(d['falseRate'])} → **{pct(b['falseRate'])}** |")
    md.append("")

    md.append(f"## Pick #1 parameters ({space} engine)")
    md.append("")
    md.append("| parameter | pick #1 |")
    md.append("|---|---:|")
    for key, value in sorted(full_params(best, space).items()):
        md.append(f"| {key} | **{value:.3g}** |" if isinstance(value, float) else f"| {key} | **{value}** |")
    md.append("")
    md.append(f"Saved to `PitchBench/tuning/recommended-{study.study_name}.json`. Nothing in the "
              "app changes until you decide to adopt these.")
    (BENCH / f"TUNING-{study.study_name}.md").write_text("\n".join(md) + "\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def full_params(trial, space: str) -> dict:
    """A trial's params plus anything its search space fixes (the engine)."""
    return ({"engine": "probabilistic"} if space == "probabilistic" else {}) | trial.params


def constraints(trial) -> list[float]:
    """≤ 0 means feasible. Trials from before this guard existed count as feasible."""
    return [MIN_TONES_COVERAGE - trial.user_attrs.get("tonesCoverage", 1.0)]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--trials", type=int, default=400)
    parser.add_argument("--jobs", type=int, default=6, help="parallel benchmark servers")
    parser.add_argument("--study", default="pitch-tracker", help="study name (resumes if it exists)")
    parser.add_argument("--report-only", action="store_true", help="re-rank the existing study, no search")
    parser.add_argument("--space", choices=sorted(SPACES), default="gated",
                        help="which engine's knobs to search (comparisons are always against "
                             "today's app defaults)")
    args = parser.parse_args()

    print("Building the benchmark…", flush=True)
    binary = subprocess.run([str(BENCH / "run.sh"), "--build"], check=True,
                            capture_output=True, text=True).stdout.strip().splitlines()[-1]

    OUT.mkdir(exist_ok=True)
    optuna.logging.set_verbosity(optuna.logging.WARNING)
    study = optuna.create_study(
        study_name=args.study, storage=f"sqlite:///{OUT / 'study.db'}", load_if_exists=True,
        directions=["maximize", "minimize", "minimize"],
        sampler=optuna.samplers.TPESampler(seed=42, multivariate=True, constraints_func=constraints))

    if not args.report_only:
        if not study.trials and args.space == "gated":
            study.enqueue_trial(DEFAULTS)
        done = [0]

        def objective(trial):
            reply = server(binary).score(SPACES[args.space](trial), ["train", "tones"])
            s = reply["train"]
            trial.set_user_attr("tonesCoverage", reply["tones"]["coverage"])
            for key in ("detectionRate", "medianLatencyMs", "jitterCents"):
                trial.set_user_attr(key, s[key])
            done[0] += 1
            if done[0] % 25 == 0:
                print(f"  {done[0]}/{args.trials} trials · front {len(study.best_trials)}", flush=True)
            return tuple(s[k] for k in OBJECTIVES)

        print(f"Searching: {args.trials} trials on {args.jobs} workers…", flush=True)
        study.optimize(objective, n_trials=args.trials, n_jobs=args.jobs)

    # Re-score the Pareto front on every split (in parallel) and rank on TEST.
    front = study.best_trials
    print(f"Re-scoring {len(front)} Pareto trials on test, recorded and clean tones…", flush=True)
    # Each worker thread talks only to its OWN server (`server()` is
    # thread-local) — a shared server would interleave requests and replies.
    with ThreadPoolExecutor(args.jobs) as ex:
        scores = list(ex.map(lambda params: full_score(server(binary), params),
                             [DEFAULTS] + [full_params(t, args.space) for t in front]))
    defaults, scored = scores[0], list(zip(front, scores[1:]))
    ranked, qualified = rank(scored, defaults)
    best = ranked[0][0]

    srv = server(binary)
    by_bg_default = srv.score(DEFAULTS, ["test"], by_background=True)["byBackground"]["test"]
    by_bg_best = srv.score(full_params(best, args.space), ["test"], by_background=True)["byBackground"]["test"]
    write_report(study, ranked, qualified, defaults, by_bg_default, by_bg_best, best, args.space)
    (OUT / f"recommended-{args.study}.json").write_text(
        json.dumps(full_params(best, args.space), indent=2, sort_keys=True) + "\n")

    for s in _servers:
        s.close()
    d, b = defaults["test"], ranked[0][1]["test"]
    print(f"\nRanking rule {'met' if qualified else 'NOT met — fell back to balanced score'}.")
    print(f"Test — defaults: coverage {pct(d['coverage'])}, wrong {pct(d['wrongRate'])}, false {pct(d['falseRate'])}")
    print(f"Test — pick #1:  coverage {pct(b['coverage'])}, wrong {pct(b['wrongRate'])}, false {pct(b['falseRate'])} "
          f"(trial {best.number}, {args.space} engine)")
    print(f"Report: {BENCH / f'TUNING-{study.study_name}.md'}")


if __name__ == "__main__":
    sys.exit(main())
