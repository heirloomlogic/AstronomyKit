#!/usr/bin/env python3
"""Measure isolated Swift startup controls for the native Sun pilot on Linux."""

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
TRIALS = 5
CONTROLS = {
    "minimalSwift": {
        "product": "AstronomyRSSMinimalSwift",
        "arguments": [],
        "mappingArguments": ["--mapping-control"],
    },
    "foundationOnly": {
        "product": "AstronomyRSSFoundationOnly",
        "arguments": [],
        "mappingArguments": ["--mapping-control"],
    },
    "modelLinked": {
        "product": "AstronomyRSSModelLinked",
        "arguments": [],
        "mappingArguments": ["--mapping-control"],
    },
    "unchangedRunner": {
        "product": "AstronomySunPilotRunner",
        "arguments": ["--rss-stage", "startup"],
        "mappingArguments": [],
    },
}


def load_module(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SUN_PILOT = load_module("sun_pilot_for_rss", "Scripts/migration/sun_pilot.py")
MEASURE = SUN_PILOT.MEASURE


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def source_hashes():
    hashes = SUN_PILOT.source_hashes()
    for relative in (
        "Scripts/migration/sun_pilot_rss.py",
        "Scripts/migration/test_sun_pilot_rss.py",
        "Tools/Migration/SunPilotRSSDiagnostics/MinimalSwiftRunner/main.swift",
        "Tools/Migration/SunPilotRSSDiagnostics/FoundationOnlyRunner/main.swift",
        "Tools/Migration/SunPilotRSSDiagnostics/ModelLinkedRunner/main.swift",
        ".github/workflows/sun-pilot-rss.yml",
        "Documentation/Migration/SunPilotRSSInvestigation.md",
    ):
        path = ROOT / relative
        if path.exists():
            hashes[relative] = MEASURE.sha256(path)
    return dict(sorted(hashes.items()))


def validate_measurements(measurements):
    if tuple(measurements) != tuple(CONTROLS):
        raise ValueError("RSS control inventory differs")
    for name, samples in measurements.items():
        if len(samples) != TRIALS:
            raise ValueError(f"{name} requires five fresh-process trials")
        for sample in samples:
            if type(sample.get("peakResidentBytes")) is not int or sample["peakResidentBytes"] <= 0:
                raise ValueError(f"{name} requires positive peak resident bytes")
            try:
                value = float(sample.get("stdout", ""))
            except (TypeError, ValueError) as error:
                raise ValueError(f"{name} produced an invalid scalar control") from error
            if not math.isfinite(value):
                raise ValueError(f"{name} produced a nonfinite scalar control")
    return measurements


def summarize_measurements(measurements, ceiling):
    validate_measurements(measurements)
    summaries = {}
    for name, samples in measurements.items():
        values = [sample["peakResidentBytes"] for sample in samples]
        summaries[name] = {
            "minimumBytes": min(values),
            "medianBytes": int(statistics.median(values)),
            "maximumBytes": max(values),
            "exceedsCeiling": min(values) > ceiling,
        }
    foundation = summaries["foundationOnly"]
    model = summaries["modelLinked"]
    runner = summaries["unchangedRunner"]
    linkage_separated = model["minimumBytes"] > foundation["maximumBytes"]
    runner_separated = runner["minimumBytes"] > foundation["maximumBytes"]
    candidate_can_meet = foundation["maximumBytes"] <= ceiling
    if summaries["minimalSwift"]["minimumBytes"] > ceiling or foundation["minimumBytes"] > ceiling:
        decision = "runtime-floor-exceeds-ceiling"
    elif linkage_separated and runner_separated and candidate_can_meet:
        decision = "candidate-linkage-cost-detected"
    elif not linkage_separated:
        decision = "no-separated-candidate-linkage-cost"
    else:
        decision = "foundation-range-not-bounded-below-ceiling"
    return {
        "ceilingBytes": ceiling,
        "controls": summaries,
        "modelLinkageRangeSeparatedFromFoundation": linkage_separated,
        "unchangedRunnerRangeSeparatedFromFoundation": runner_separated,
        "modelLinkedMedianDeltaFromFoundationBytes": model["medianBytes"] - foundation["medianBytes"],
        "unchangedRunnerMedianDeltaFromFoundationBytes": runner["medianBytes"] - foundation["medianBytes"],
        "candidateRemovalCanMeetCeiling": candidate_can_meet,
        "decision": decision,
    }


def run_logged(command, cwd):
    started = time.perf_counter()
    process = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    MEASURE.ACTIVE_LOG.save(command, cwd, process.stdout, process.stderr, process.returncode, elapsed_seconds=time.perf_counter() - started)
    process.check_returncode()
    return process.stdout


def build_product(package, scratch, product):
    command = ["swift", "build", "-c", "release", "--product", product, "--scratch-path", str(scratch)]
    run_logged(command, package)


def measure_process(binary, arguments):
    with tempfile.NamedTemporaryFile() as stream:
        time_path = Path(stream.name)
        command = [*MEASURE.time_arguments(time_path), str(binary), *arguments]
        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        MEASURE.ACTIVE_LOG.save(command, ROOT, process.stdout, process.stderr, process.returncode, time_path.read_text())
        process.check_returncode()
        return {"peakResidentBytes": MEASURE.parse_rss(time_path), "stdout": process.stdout}


def retain_command_output(output, name, command, binary):
    contents = run_logged([*command, str(binary)], ROOT)
    path = output / "linkage" / f"{name}.{'-'.join(command)}.txt"
    path.write_text(contents)
    return {"path": path.relative_to(output).as_posix(), "sha256": MEASURE.sha256(path)}


def retain_mapping(output, name, binary, arguments, package):
    process = subprocess.Popen([str(binary), *arguments], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    maps_path = Path(f"/proc/{process.pid}/maps")
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and process.poll() is None:
        if maps_path.exists() and str(binary) in maps_path.read_text():
            break
        time.sleep(0.01)
    if process.poll() is not None or not maps_path.exists():
        stdout, stderr = process.communicate(timeout=1)
        raise RuntimeError(f"{name} did not remain alive for a mapping snapshot: {stdout}{stderr}")
    contents = maps_path.read_text().replace(str(package), "$PACKAGE")
    path = output / "linkage" / f"{name}.proc-maps.txt"
    path.write_text(contents)
    stdout, stderr = process.communicate(input="", timeout=5)
    if process.returncode:
        raise subprocess.CalledProcessError(process.returncode, [str(binary), *arguments], stdout, stderr)
    return {
        "path": path.relative_to(output).as_posix(),
        "sha256": MEASURE.sha256(path),
        "mappingCount": len(contents.splitlines()),
        "snapshotPoint": "ready for stdin before scalar output" if arguments else "unchanged runner ready for numerical stdin",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    if platform.system() != "Linux":
        parser.error("the RSS attribution campaign requires Linux")
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / "linkage").mkdir()
    MEASURE.ACTIVE_LOG = MEASURE.CommandLog(output / "logs")
    inputs = source_hashes()
    baseline = ROOT / "Documentation/Migration/performance-baseline.json"
    budget = json.loads(baseline.read_text())["budgets"]["peakResidentBytes"]
    report = {
        "schemaVersion": 1,
        "status": "running",
        "qualified": False,
        "candidateRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "candidateDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
        "environment": {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "system": platform.system(),
            "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
        },
        "fixedCeiling": {"peakResidentBytes": budget, "baselineSHA256": MEASURE.sha256(baseline)},
        "sourceSHA256": inputs,
        "trialCount": TRIALS,
        "freshProcessPerTrial": True,
    }
    write_json(output / "report.json", report)
    measurements = {}
    binaries = {}
    with tempfile.TemporaryDirectory(prefix="sun-pilot-rss-package-") as temporary:
        package = Path(temporary) / "package"
        evaluated_manifest = SUN_PILOT.prepare_package(package)
        report["effectivePackage"] = {
            "developmentManifest": "Tools/Migration/SunPilotPackage/Package.swift",
            "manifestSHA256": MEASURE.sha256(package / "Package.swift"),
            "evaluatedManifestSHA256": hashlib.sha256(json.dumps(evaluated_manifest, sort_keys=True).encode()).hexdigest(),
            "evaluatedManifest": evaluated_manifest,
        }
        scratch = package / ".build/rss-attribution-release"
        for name, control in CONTROLS.items():
            build_product(package, scratch, control["product"])
        binary_directory = Path(run_logged(["swift", "build", "-c", "release", "--show-bin-path", "--scratch-path", str(scratch)], package).strip())
        for name, control in CONTROLS.items():
            binary = binary_directory / control["product"]
            measurements[name] = [measure_process(binary, control["arguments"]) for _ in range(TRIALS)]
            binaries[name] = {
                "product": control["product"],
                "sha256": MEASURE.sha256(binary),
                "bytes": binary.stat().st_size,
                "arguments": control["arguments"],
                "file": retain_command_output(output, name, ["file"], binary),
                "dynamicLinkage": retain_command_output(output, name, ["ldd"], binary),
                "symbols": retain_command_output(output, name, ["nm", "-S", "--size-sort"], binary),
                "elfProgramHeaders": retain_command_output(output, name, ["readelf", "-W", "-l"], binary),
                "elfDynamicSection": retain_command_output(output, name, ["readelf", "-W", "-d"], binary),
                "elfNotes": retain_command_output(output, name, ["readelf", "-W", "-n"], binary),
                "processMappings": retain_mapping(output, name, binary, control["mappingArguments"], package),
            }
    validate_measurements(measurements)
    MEASURE.require_unchanged_snapshot(inputs, source_hashes())
    report.update({
        "status": "complete-evidence",
        "measurements": measurements,
        "summary": summarize_measurements(measurements, budget),
        "binaries": binaries,
        "commandLogs": MEASURE.ACTIVE_LOG.receipt(),
        "unmetGates": [
            "This startup attribution campaign does not execute the frozen mixed astronomical workload.",
            "The full issue still requires comparable-runtime latency and throughput evidence and independent review.",
        ],
    })
    write_json(output / "report.json", report)
    print(json.dumps(report["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
