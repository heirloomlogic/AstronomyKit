#!/usr/bin/env python3

import argparse
import hashlib
import json
import math
import os
import platform
import re
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
PROVENANCE_FIELDS = (
    "baseRevision",
    "environment",
    "commands",
    "inputSHA256",
    "protocol",
    "runnerSHA256",
    "runnerChecksums",
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
    record = {
        "schemaVersion": 1,
        "baseRevision": "0" * 40,
        "scope": "test fixture",
        "environment": {
            "system": "test",
            "machine": "test",
            "hardwareModel": "test",
            "platform": "test",
            "processorCount": 1,
            "swift": "test",
            "clang": "test",
        },
        "commands": measurement_commands(),
        "inputSHA256": {"fixture": "0" * 64},
        "protocol": {
            "schemaVersion": 1,
            "commands": measurement_commands(),
            "buildWarmupRuns": 1,
            "buildTrials": BUILD_TRIALS,
            "runtimeTrials": RUNTIME_TRIALS,
            "coordinatorSHA256": "0" * 64,
            "runnerSourceSHA256": "0" * 64,
        },
        "runnerSHA256": "0" * 64,
        "runnerChecksums": [{"representativeLatency": 1.0, "coldThroughput": 2.0, "warmThroughput": 3.0}] * RUNTIME_TRIALS,
        "measurements": measurements,
        "budgets": derive_budgets(measurements),
    }
    record["provenanceSHA256"] = provenance_sha256(record)
    return record


def measurement_commands():
    return {
        "runtime": ["{runner}"],
        "build": [
            "swift",
            "build",
            "-c",
            "release",
            "--product",
            "AstronomyMigrationPerformanceRunner",
            "--scratch-path",
            "{scratch}",
        ],
    }


def provenance_sha256(record):
    provenance = {field: record.get(field) for field in PROVENANCE_FIELDS}
    payload = json.dumps(provenance, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return hashlib.sha256(payload).hexdigest()


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
    revision = record.get("baseRevision")
    if not isinstance(revision, str) or re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        raise ValueError("baseRevision must be a full lowercase Git object identifier")
    expected_environment = {"system", "machine", "hardwareModel", "platform", "processorCount", "swift", "clang"}
    environment_record = record.get("environment")
    if not isinstance(environment_record, dict) or set(environment_record) != expected_environment:
        raise ValueError("environment is incomplete")
    if not all(environment_record[key] for key in expected_environment - {"processorCount"}):
        raise ValueError("environment contains an empty value")
    if not isinstance(environment_record["processorCount"], int) or environment_record["processorCount"] <= 0:
        raise ValueError("environment processorCount must be positive")
    if record.get("commands") != measurement_commands():
        raise ValueError("commands do not match the measurement protocol")
    inputs = record.get("inputSHA256")
    if not isinstance(inputs, dict) or not inputs or not all(isinstance(path, str) and path and isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) for path, digest in inputs.items()):
        raise ValueError("inputSHA256 is invalid")
    protocol = record.get("protocol")
    if not isinstance(protocol, dict) or protocol.get("schemaVersion") != 1 or protocol.get("commands") != measurement_commands():
        raise ValueError("measurement protocol is invalid")
    if protocol.get("buildWarmupRuns") != 1 or protocol.get("buildTrials") != BUILD_TRIALS or protocol.get("runtimeTrials") != RUNTIME_TRIALS:
        raise ValueError("measurement protocol workload is invalid")
    for field in ("coordinatorSHA256", "runnerSourceSHA256"):
        if not isinstance(protocol.get(field), str) or re.fullmatch(r"[0-9a-f]{64}", protocol[field]) is None:
            raise ValueError(f"measurement protocol {field} is invalid")
    runner_hash = record.get("runnerSHA256")
    if not isinstance(runner_hash, str) or re.fullmatch(r"[0-9a-f]{64}", runner_hash) is None:
        raise ValueError("runnerSHA256 is invalid")
    checksums = record.get("runnerChecksums")
    checksum_keys = {"representativeLatency", "coldThroughput", "warmThroughput"}
    if not isinstance(checksums, list) or len(checksums) != RUNTIME_TRIALS:
        raise ValueError("runnerChecksums must contain five trials")
    if not all(isinstance(checksum, dict) and set(checksum) == checksum_keys and all(isinstance(value, (int, float)) and math.isfinite(value) for value in checksum.values()) for checksum in checksums):
        raise ValueError("runnerChecksums contains an invalid checksum")
    if any(checksum != checksums[0] for checksum in checksums[1:]):
        raise ValueError("runnerChecksums changed between trials")
    if record.get("provenanceSHA256") != provenance_sha256(record):
        raise ValueError("performance baseline provenance checksum does not match")
    return record


def run(command, cwd=ROOT, **kwargs):
    return subprocess.run(command, cwd=cwd, check=True, text=True, **kwargs)


def command_output(command, cwd=ROOT):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def source_hashes(root=ROOT):
    paths = [root / relative for relative in INPUT_PATHS]
    paths.extend(sorted((root / "Sources/AstronomyKit").rglob("*.swift")))
    paths.extend(sorted(path for path in (root / "Sources/CLibAstronomy").rglob("*") if path.is_file()))
    return {path.relative_to(root).as_posix(): sha256(path) for path in paths}


def copy_measurement_workspace(source, destination):
    destination.mkdir()
    shutil.copy2(source / "Package.swift", destination / "Package.swift")
    shutil.copytree(source / "Sources", destination / "Sources")
    shutil.copytree(source / "Tests", destination / "Tests")
    shutil.copytree(source / "Tools", destination / "Tools")


def remove_scratch(scratch):
    if scratch.exists():
        shutil.rmtree(scratch)


def capture_snapshot():
    return {"baseRevision": command_output(["git", "rev-parse", "HEAD"]), "inputSHA256": source_hashes()}


def require_unchanged_snapshot(before, after):
    if before != after:
        raise RuntimeError("sources changed during measurement")


def build_measurements(package_root, scratch):
    command = ["swift", "build", "-c", "release", "--product", "AstronomyMigrationPerformanceRunner", "--scratch-path", str(scratch)]
    run(command, cwd=package_root, stdout=subprocess.DEVNULL)
    clean = []
    for _ in range(BUILD_TRIALS):
        remove_scratch(scratch)
        started = time.perf_counter()
        run(command, cwd=package_root, stdout=subprocess.DEVNULL)
        clean.append(time.perf_counter() - started)
    incremental = []
    source = package_root / "Sources/AstronomyKit/AstronomyKit.swift"
    original_times = source.stat()
    try:
        for index in range(BUILD_TRIALS):
            timestamp = time.time() + index + 1
            os.utime(source, (timestamp, timestamp))
            started = time.perf_counter()
            run(command, cwd=package_root, stdout=subprocess.DEVNULL)
            incremental.append(time.perf_counter() - started)
    finally:
        os.utime(source, ns=(original_times.st_atime_ns, original_times.st_mtime_ns))
    bin_path = command_output(["swift", "build", "-c", "release", "--show-bin-path", "--scratch-path", str(scratch)], cwd=package_root)
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
    before = capture_snapshot()
    measured_environment = environment()
    with tempfile.TemporaryDirectory(prefix="astronomykit-performance-workspace-") as temporary:
        package_root = Path(temporary) / "package"
        copy_measurement_workspace(ROOT, package_root)
        scratch = package_root / ".build/migration-performance-baseline"
        _, clean, incremental, executable = build_measurements(package_root, scratch)
        runtime, checksums = runtime_measurements(executable)
        runtime["strippedBinaryBytes"] = stripped_size(executable)
        runtime["cleanBuildSeconds"] = clean
        runtime["incrementalBuildSeconds"] = incremental
        after = capture_snapshot()
        require_unchanged_snapshot(before, after)
        record = {
            "schemaVersion": 1,
            "baseRevision": before["baseRevision"],
            "scope": "Pure-Swift migration pilot measured on the recorded host and toolchain",
            "environment": measured_environment,
            "commands": measurement_commands(),
            "inputSHA256": before["inputSHA256"],
            "protocol": {
                "schemaVersion": 1,
                "commands": measurement_commands(),
                "buildWarmupRuns": 1,
                "buildTrials": BUILD_TRIALS,
                "runtimeTrials": RUNTIME_TRIALS,
                "coordinatorSHA256": before["inputSHA256"]["Scripts/migration/performance_baseline.py"],
                "runnerSourceSHA256": before["inputSHA256"]["Tools/Migration/PerformanceRunner/main.swift"],
            },
            "runnerSHA256": sha256(executable),
            "runnerChecksums": checksums,
            "measurements": runtime,
            "budgets": derive_budgets(runtime),
        }
        record["provenanceSHA256"] = provenance_sha256(record)
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


def validate_candidate_protocol(baseline, candidate):
    if candidate["protocol"] != baseline["protocol"]:
        raise ValueError("candidate measurement protocol differs from the baseline")


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
    validate_candidate_protocol(baseline, candidate)
    result = evaluate_candidate(baseline, candidate["measurements"])
    print(json.dumps({"candidate": candidate, "evaluation": result}, indent=2, sort_keys=True))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
