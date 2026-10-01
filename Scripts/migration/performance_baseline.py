#!/usr/bin/env python3

import argparse
import hashlib
import json
import math
import os
import platform
import shutil
import statistics
import subprocess
import tempfile
import time
from decimal import Decimal, ROUND_CEILING
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASELINE_PATH = ROOT / "Documentation/Migration/performance-baseline.json"
RUNTIME_TRIALS = 5
BUILD_TRIALS = 3
RUNTIME_METRICS = (
    "latencyNanosecondsPerOperation",
    "coldThroughputOperationsPerSecond",
    "warmThroughputOperationsPerSecond",
    "peakResidentBytes",
)
BUILD_METRICS = ("cleanBuildSeconds", "incrementalBuildSeconds")
INPUT_PATHS = (
    "Package.swift",
    "Scripts/migration/performance_baseline.py",
    "Tools/Migration/PerformanceRunner/main.swift",
)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rounded_up(value, digits=0):
    quantum = Decimal(1).scaleb(-digits)
    normalized = Decimal(str(value)).quantize(Decimal("0.000000000001"))
    return float(normalized.quantize(quantum, rounding=ROUND_CEILING))


def derive_budgets(measurements):
    return {
        "latencyNanosecondsPerOperation": math.ceil(statistics.median(measurements["latencyNanosecondsPerOperation"]) * 1.5),
        "coldThroughputOperationsPerSecond": math.floor(statistics.median(measurements["coldThroughputOperationsPerSecond"]) * 0.8),
        "warmThroughputOperationsPerSecond": math.floor(statistics.median(measurements["warmThroughputOperationsPerSecond"]) * 0.8),
        "peakResidentBytes": math.ceil(max(measurements["peakResidentBytes"]) * 1.25),
        "strippedBinaryBytes": math.ceil(measurements["strippedBinaryBytes"] * 1.1),
        "cleanBuildSeconds": rounded_up(max(measurements["cleanBuildSeconds"]) * 1.5, 3),
        "incrementalBuildSeconds": rounded_up(max(measurements["incrementalBuildSeconds"]) * 1.5, 3),
    }


def candidate_summary(measurements):
    return {
        "latencyNanosecondsPerOperation": statistics.median(measurements["latencyNanosecondsPerOperation"]),
        "coldThroughputOperationsPerSecond": statistics.median(measurements["coldThroughputOperationsPerSecond"]),
        "warmThroughputOperationsPerSecond": statistics.median(measurements["warmThroughputOperationsPerSecond"]),
        "peakResidentBytes": max(measurements["peakResidentBytes"]),
        "strippedBinaryBytes": measurements["strippedBinaryBytes"],
        "cleanBuildSeconds": max(measurements["cleanBuildSeconds"]),
        "incrementalBuildSeconds": max(measurements["incrementalBuildSeconds"]),
    }


def evaluate_candidate(baseline, measurements):
    summary = candidate_summary(measurements)
    budgets = baseline["budgets"]
    lower_is_better = {
        "latencyNanosecondsPerOperation",
        "peakResidentBytes",
        "strippedBinaryBytes",
        "cleanBuildSeconds",
        "incrementalBuildSeconds",
    }
    failures = []
    for metric, value in summary.items():
        if metric in lower_is_better and value > budgets[metric]:
            failures.append(metric)
        if metric not in lower_is_better and value < budgets[metric]:
            failures.append(metric)
    return {"passed": not failures, "failures": failures, "summary": summary}


def make_record_for_test(measurements):
    return {
        "schemaVersion": 1,
        "baseRevision": "0" * 40,
        "scope": "test fixture",
        "environment": {"system": "test", "machine": "test", "swift": "test", "clang": "test"},
        "commands": {"runtime": ["runner"], "build": ["swift", "build"]},
        "inputSHA256": {"fixture": "0" * 64},
        "runnerSHA256": "0" * 64,
        "measurements": measurements,
        "budgets": derive_budgets(measurements),
    }


def validate_record(record):
    if record.get("schemaVersion") != 1:
        raise ValueError("unsupported performance baseline schema")
    measurements = record.get("measurements", {})
    for metric in RUNTIME_METRICS:
        values = measurements.get(metric)
        if not isinstance(values, list) or len(values) != RUNTIME_TRIALS:
            raise ValueError(f"{metric} must contain five trials")
        if not all(isinstance(value, (int, float)) and math.isfinite(value) and value > 0 for value in values):
            raise ValueError(f"{metric} contains an invalid measurement")
    for metric in BUILD_METRICS:
        values = measurements.get(metric)
        if not isinstance(values, list) or len(values) != BUILD_TRIALS:
            raise ValueError(f"{metric} must contain three trials")
        if not all(isinstance(value, (int, float)) and math.isfinite(value) and value > 0 for value in values):
            raise ValueError(f"{metric} contains an invalid measurement")
    binary_size = measurements.get("strippedBinaryBytes")
    if not isinstance(binary_size, int) or binary_size <= 0:
        raise ValueError("strippedBinaryBytes must be a positive integer")
    if record.get("budgets") != derive_budgets(measurements):
        raise ValueError("budgets do not match the recorded measurements")
    return record


def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, check=True, text=True, **kwargs)


def command_output(command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def source_hashes():
    paths = [ROOT / relative for relative in INPUT_PATHS]
    paths.extend(sorted((ROOT / "Sources/AstronomyKit").glob("*.swift")))
    paths.extend(sorted(path for path in (ROOT / "Sources/CLibAstronomy").rglob("*") if path.is_file()))
    return {path.relative_to(ROOT).as_posix(): sha256(path) for path in paths}


def without_dev_tooling(operation):
    sentinel = ROOT / ".dev-tooling"
    parked = ROOT / ".dev-tooling.performance-baseline"
    if parked.exists():
        raise RuntimeError(f"temporary sentinel path already exists: {parked}")
    moved = sentinel.exists()
    if moved:
        sentinel.rename(parked)
    try:
        return operation()
    finally:
        if moved:
            parked.rename(sentinel)


def build_measurements(scratch):
    command = ["swift", "build", "-c", "release", "--product", "AstronomyMigrationPerformanceRunner", "--scratch-path", str(scratch)]
    clean = []
    for _ in range(BUILD_TRIALS):
        shutil.rmtree(scratch, ignore_errors=True)
        started = time.perf_counter()
        run(command, stdout=subprocess.DEVNULL)
        clean.append(time.perf_counter() - started)
    incremental = []
    source = ROOT / "Sources/AstronomyKit/AstronomyKit.swift"
    original_times = source.stat()
    try:
        for index in range(BUILD_TRIALS):
            timestamp = time.time() + index + 1
            os.utime(source, (timestamp, timestamp))
            started = time.perf_counter()
            run(command, stdout=subprocess.DEVNULL)
            incremental.append(time.perf_counter() - started)
    finally:
        os.utime(source, ns=(original_times.st_atime_ns, original_times.st_mtime_ns))
    bin_path = command_output(["swift", "build", "-c", "release", "--show-bin-path", "--scratch-path", str(scratch)])
    return command, clean, incremental, Path(bin_path) / "AstronomyMigrationPerformanceRunner"


def stripped_size(executable):
    with tempfile.TemporaryDirectory(prefix="astronomykit-performance-strip-") as directory:
        copy = Path(directory) / executable.name
        shutil.copy2(executable, copy)
        strip = shutil.which("strip")
        if strip is None:
            raise RuntimeError("strip is required to measure the release binary")
        run([strip, "-S" if platform.system() == "Darwin" else "--strip-debug", str(copy)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return copy.stat().st_size


def parse_peak_resident(path):
    text = path.read_text()
    if platform.system() == "Darwin":
        for line in text.splitlines():
            if "maximum resident set size" in line:
                return int(line.split()[0])
    else:
        for line in text.splitlines():
            if "Maximum resident set size" in line:
                return int(line.rsplit(":", 1)[1].strip()) * 1024
    raise RuntimeError("time output did not contain peak resident memory")


def runtime_measurements(executable):
    time_tool = "/usr/bin/time"
    measurements = {metric: [] for metric in RUNTIME_METRICS}
    checksums = []
    for _ in range(RUNTIME_TRIALS):
        with tempfile.NamedTemporaryFile(prefix="astronomykit-performance-time-", delete=False) as stream:
            time_path = Path(stream.name)
        try:
            time_arguments = [time_tool, "-l", "-o", str(time_path)] if platform.system() == "Darwin" else [time_tool, "-v", "-o", str(time_path)]
            completed = run([*time_arguments, str(executable)], capture_output=True)
            report = json.loads(completed.stdout)
            latency = report["representativeLatency"]
            cold = report["coldThroughput"]
            warm = report["warmThroughput"]
            measurements["latencyNanosecondsPerOperation"].append(latency["elapsedNanoseconds"] / latency["operations"])
            measurements["coldThroughputOperationsPerSecond"].append(cold["operations"] * 1_000_000_000 / cold["elapsedNanoseconds"])
            measurements["warmThroughputOperationsPerSecond"].append(warm["operations"] * 1_000_000_000 / warm["elapsedNanoseconds"])
            measurements["peakResidentBytes"].append(parse_peak_resident(time_path))
            checksums.append({name: report[name]["checksum"] for name in ("representativeLatency", "coldThroughput", "warmThroughput")})
        finally:
            time_path.unlink(missing_ok=True)
    if any(value != checksums[0] for value in checksums[1:]):
        raise RuntimeError("performance runner checksums changed between trials")
    return measurements, checksums


def environment():
    hardware_model = command_output(["sysctl", "-n", "hw.model"]) if platform.system() == "Darwin" else platform.machine()
    return {
        "system": platform.system(),
        "machine": platform.machine(),
        "hardwareModel": hardware_model,
        "platform": platform.platform(),
        "processorCount": os.cpu_count(),
        "swift": command_output(["swift", "--version"]),
        "clang": command_output(["clang", "--version"]).splitlines()[0],
    }


def measure():
    scratch = ROOT / ".build/migration-performance-baseline"

    def operation():
        build_command, clean, incremental, executable = build_measurements(scratch)
        runtime, checksums = runtime_measurements(executable)
        runtime["strippedBinaryBytes"] = stripped_size(executable)
        runtime["cleanBuildSeconds"] = clean
        runtime["incrementalBuildSeconds"] = incremental
        return build_command, executable, runtime, checksums

    build_command, executable, measurements, checksums = without_dev_tooling(operation)
    record = {
        "schemaVersion": 1,
        "baseRevision": command_output(["git", "rev-parse", "HEAD"]),
        "scope": "Pure-Swift migration pilot measured on the recorded host and toolchain",
        "environment": environment(),
        "commands": {"runtime": [str(executable)], "build": build_command},
        "inputSHA256": source_hashes(),
        "runnerSHA256": sha256(executable),
        "runnerChecksums": checksums,
        "measurements": measurements,
        "budgets": derive_budgets(measurements),
    }
    validate_record(record)
    return record


def check_record(record):
    validate_record(record)
    current = source_hashes()
    if record.get("inputSHA256") != current:
        raise ValueError("performance baseline input hashes are stale")
    result = evaluate_candidate(record, record["measurements"])
    if not result["passed"]:
        raise ValueError(f"recorded baseline fails its own budgets: {result['failures']}")
    return result


def main():
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    action.add_argument("--compare", action="store_true")
    arguments = parser.parse_args()
    if arguments.write:
        record = measure()
        BASELINE_PATH.parent.mkdir(parents=True, exist_ok=True)
        BASELINE_PATH.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
        print(f"Wrote {BASELINE_PATH.relative_to(ROOT)}")
        return
    if not BASELINE_PATH.exists():
        raise SystemExit(f"missing {BASELINE_PATH.relative_to(ROOT)}")
    baseline = json.loads(BASELINE_PATH.read_text())
    if arguments.check:
        result = check_record(baseline)
        print(json.dumps(result, indent=2, sort_keys=True))
        return
    candidate = measure()
    if candidate["environment"] != baseline["environment"]:
        raise SystemExit("candidate environment differs from the recorded baseline; record a new baseline instead")
    result = evaluate_candidate(baseline, candidate["measurements"])
    print(json.dumps({"candidate": candidate, "evaluation": result}, indent=2, sort_keys=True))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
