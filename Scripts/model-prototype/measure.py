#!/usr/bin/env python3
"""Measure the complete Swift model prototype without regenerating it."""

import re
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / "Documentation/Migration/performance-baseline.json"
OUTPUT = ROOT / "Documentation/Migration/model-prototype-evidence.json"
BUILD_TRIALS = 3
RUNTIME_TRIALS = 5


def evaluate_builds(measurements, budgets):
    summary = {
        "cleanReleaseSeconds": max(measurements["cleanReleaseSeconds"]),
        "incrementalReleaseSeconds": max(measurements["incrementalReleaseSeconds"]),
    }
    mapping = {"cleanReleaseSeconds": "cleanBuildSeconds", "incrementalReleaseSeconds": "incrementalBuildSeconds"}
    failures = [metric for metric, budget in mapping.items() if summary[metric] > budgets[budget]]
    return {"summary": summary, "failures": failures, "passed": not failures}


def validate_evidence(record):
    if len(record.get("cleanReleaseSeconds", [])) != 3:
        raise ValueError("three clean Release trials are required")
    if len(record.get("incrementalReleaseSeconds", [])) != 3:
        raise ValueError("three incremental Release trials are required")
    if re.fullmatch(r"[0-9a-f]{64}", record.get("workloadSHA256", "")) is None:
        raise ValueError("workload SHA-256 is invalid")
    return record


def write_checkpoint(path, phase, measurements, failure=None):
    record = {
        "schemaVersion": 1,
        "status": "incomplete" if failure else "running",
        "phase": phase,
        "measurements": measurements,
    }
    if failure:
        record["failure"] = failure
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prototype_inputs(root):
    paths = [root / "Package.swift", root / "Tools/Migration/ModelPrototypeRunner/main.swift"]
    paths.extend(sorted(path for path in (root / "Sources").rglob("*") if path.is_file() and "Prototype" in path.as_posix()))
    return {path.relative_to(root).as_posix(): sha256(path) for path in paths}


def copy_workspace(destination):
    destination.mkdir()
    shutil.copy2(ROOT / "Package.swift", destination / "Package.swift")
    shutil.copytree(ROOT / "Sources", destination / "Sources")
    shutil.copytree(ROOT / "Tests", destination / "Tests")
    shutil.copytree(ROOT / "Tools", destination / "Tools")
    (destination / ".model-prototype").touch()


def parse_rss(path):
    for line in path.read_text().splitlines():
        if "maximum resident set size" in line:
            return int(line.split()[0])
    raise RuntimeError("compiler RSS was not recorded")


def timed_build(package, scratch, configuration):
    command = ["swift", "build", "-c", configuration, "--product", "AstronomyModelPrototypeRunner", "--scratch-path", str(scratch)]
    with tempfile.NamedTemporaryFile(prefix="model-prototype-time-", delete=False) as stream:
        time_path = Path(stream.name)
    try:
        started = time.perf_counter()
        subprocess.run(["/usr/bin/time", "-l", "-o", str(time_path), *command], cwd=package, check=True, stdout=subprocess.DEVNULL)
        return time.perf_counter() - started, parse_rss(time_path)
    finally:
        time_path.unlink(missing_ok=True)


def build_trials(package, configuration, checkpoint=None):
    scratch = package / f".build/model-prototype-{configuration}"
    timed_build(package, scratch, configuration)
    clean_seconds, clean_rss = [], []
    for _ in range(BUILD_TRIALS):
        if scratch.exists():
            shutil.rmtree(scratch)
        seconds, rss = timed_build(package, scratch, configuration)
        clean_seconds.append(seconds)
        clean_rss.append(rss)
        if checkpoint:
            checkpoint(f"{configuration}-clean-{len(clean_seconds)}", {f"clean{configuration.title()}Seconds": clean_seconds, f"{configuration}CompilerPeakResidentBytes": clean_rss})
    source = package / "Sources/AstronomyModelPrototype/ModelData.swift"
    original = source.stat()
    incremental_seconds, incremental_rss = [], []
    try:
        for index in range(BUILD_TRIALS):
            stamp = time.time() + index + 1
            os.utime(source, (stamp, stamp))
            seconds, rss = timed_build(package, scratch, configuration)
            incremental_seconds.append(seconds)
            incremental_rss.append(rss)
            if checkpoint:
                checkpoint(f"{configuration}-incremental-{len(incremental_seconds)}", {f"clean{configuration.title()}Seconds": clean_seconds, f"incremental{configuration.title()}Seconds": incremental_seconds, f"{configuration}CompilerPeakResidentBytes": clean_rss, f"incremental{configuration.title()}PeakResidentBytes": incremental_rss})
    finally:
        os.utime(source, ns=(original.st_atime_ns, original.st_mtime_ns))
    bin_path = subprocess.check_output(["swift", "build", "-c", configuration, "--show-bin-path", "--scratch-path", str(scratch)], cwd=package, text=True).strip()
    return {
        "cleanSeconds": clean_seconds,
        "cleanPeakResidentBytes": clean_rss,
        "incrementalSeconds": incremental_seconds,
        "incrementalPeakResidentBytes": incremental_rss,
    }, Path(bin_path) / "AstronomyModelPrototypeRunner"


def timed_runner(executable, mode):
    with tempfile.NamedTemporaryFile(prefix="model-prototype-runtime-", delete=False) as stream:
        time_path = Path(stream.name)
    try:
        completed = subprocess.run(["/usr/bin/time", "-l", "-o", str(time_path), str(executable), mode], check=True, capture_output=True, text=True)
        return json.loads(completed.stdout), parse_rss(time_path)
    finally:
        time_path.unlink(missing_ok=True)


def stripped_size(executable):
    with tempfile.TemporaryDirectory(prefix="model-prototype-strip-") as directory:
        copy = Path(directory) / executable.name
        shutil.copy2(executable, copy)
        subprocess.run(["strip", "-S", str(copy)], check=True)
        return copy.stat().st_size


def environment():
    return {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
        "processorCount": os.cpu_count(),
    }


def measure():
    before = prototype_inputs(ROOT)
    partial = {}

    def checkpoint(phase, values):
        partial.update(values)
        write_checkpoint(OUTPUT, phase, partial)

    write_checkpoint(OUTPUT, "initializing", partial)
    with tempfile.TemporaryDirectory(prefix="astronomy-model-prototype-") as directory:
        package = Path(directory) / "package"
        copy_workspace(package)
        try:
            release, executable = build_trials(package, "release", checkpoint)
        except Exception as error:
            write_checkpoint(OUTPUT, "release-build", partial, str(error))
            raise
        first = [timed_runner(executable, "first") for _ in range(RUNTIME_TRIALS)]
        sweep = [timed_runner(executable, "sweep") for _ in range(RUNTIME_TRIALS)]
        measurements = {
            "cleanReleaseSeconds": release["cleanSeconds"],
            "incrementalReleaseSeconds": release["incrementalSeconds"],
            "releaseCompilerPeakResidentBytes": release["cleanPeakResidentBytes"],
            "cleanDebugBuildCompleted": False,
            "cleanDebugBuildLowerBoundSeconds": 180,
            "firstAccessNanoseconds": [item[0]["elapsedNanoseconds"] for item in first],
            "firstAccessPeakResidentBytes": [item[1] for item in first],
            "fullSweepNanoseconds": [item[0]["elapsedNanoseconds"] for item in sweep],
            "fullSweepPeakResidentBytes": [item[1] for item in sweep],
            "strippedExecutableBytes": stripped_size(executable),
        }
    after = prototype_inputs(ROOT)
    if before != after:
        raise RuntimeError("prototype inputs changed during measurement")
    baseline = json.loads(BASELINE.read_text())
    result = evaluate_builds(measurements, baseline["budgets"])
    record = {
        "schemaVersion": 1,
        "status": "incomplete",
        "phase": "measured-with-acceptance-gaps",
        "scope": "Development-only full Swift coefficient representation",
        "environment": environment(),
        "inputSHA256": before,
        "workloadSHA256": before["Tools/Migration/ModelPrototypeRunner/main.swift"],
        "measurements": measurements,
        "fixedBudgets": baseline["budgets"],
        "releaseBuildEvaluation": result,
        "consumerPackaging": {"scriptsCopied": False, "runtimeDataFiles": False, "networkDependencies": False},
        "limitations": [
            "The first-access and full-sweep workloads are representation probes, not the issue #80 astronomical request workload.",
            "Issue #80 latency and throughput gates cannot be evaluated until issue #83 supplies the Sun-path calculation.",
            "Full-sweep RSS touches every table page and is reported separately from first access and the issue #80 workload.",
            "This record covers the recorded Apple host and toolchain; Linux wall-clock and peak-memory measurements are absent.",
            "An isolated modular Debug preflight was terminated after 180 seconds without completing, so Debug artifact, incremental-build, and runtime measurements are absent.",
        ],
    }
    validate_evidence(measurements | {"workloadSHA256": record["workloadSHA256"]})
    OUTPUT.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    return record


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--measure", action="store_true")
    args = parser.parse_args()
    if not args.measure:
        parser.error("--measure is required")
    print(json.dumps(measure(), indent=2, sort_keys=True))
