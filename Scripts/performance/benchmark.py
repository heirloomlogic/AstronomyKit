#!/usr/bin/env python3
"""Reproduce issue #33 native and optimized public-Swift throughput evidence."""

import argparse
import gc
import hashlib
import json
import math
import platform
import statistics
import struct
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASELINE = "8e88bb462364265a66cf78c10a6e5932b17fad0b"
RESTORED = "c0322c2de061bf8c1d11b065040edd2953f767d6"
BODIES = ["mercury", "venus", "mars", "jupiter", "saturn", "uranus", "neptune", "sun"]
WORKLOADS = {
    "coldStream": [9000 + index * 0.125 for index in range(200)],
    "hotSameEpoch": [9000.0] * 200,
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_c(root, output, name, source):
    croot = root / "Sources/CLibAstronomy"
    suffix = ".dylib" if sys.platform == "darwin" else ".so"
    library = output / f"{name}{suffix}"
    command = [
        "clang", "-O2", "-dynamiclib" if sys.platform == "darwin" else "-shared",
        "-fPIC", "-pthread", "-I", str(croot / "include"), "-I", str(croot),
        "-I", str(croot / "generated"), str(source), str(root / "Scripts/accuracy/sample.c"),
        *map(str, sorted((croot / "detmath").glob("*.c"))), "-lm", "-o", str(library),
    ]
    subprocess.run(command, check=True)
    return {"path": str(library), "sourceSHA256": sha256(source),
            "binarySHA256": sha256(library), "compileCommand": command}


def native_trial(model, epochs):
    checksum = 0.0
    started = time.perf_counter_ns()
    for ut in epochs:
        for body in BODIES:
            values = model.position(body, ut)
            if not all(math.isfinite(value) for value in values):
                raise RuntimeError(f"non-finite output for {body} at UT {ut}")
            checksum += values[0] + values[1] + values[2] * 1e-9
    return (time.perf_counter_ns() - started) / 1e9, checksum


def native_report(models):
    results = {}
    gc.disable()
    try:
        for workload, epochs in WORKLOADS.items():
            warmup = {name: native_trial(model, epochs)[0] for name, model in models.items()}
            trials = {name: [] for name in models}
            checksums = {name: [] for name in models}
            for _ in range(5):
                for name, model in models.items():
                    elapsed, checksum = native_trial(model, epochs)
                    trials[name].append(elapsed)
                    checksums[name].append(checksum)
            medians = {name: statistics.median(values) for name, values in trials.items()}
            results[workload] = {
                "warmupSeconds": warmup, "trialsSeconds": trials, "medianSeconds": medians,
                "checksums": checksums,
                "restoredSlowdownVsBaseline": medians["restored"] / medians["baseline"],
                "candidateSpeedupVsRestored": medians["restored"] / medians["candidate"],
                "candidateSlowdownVsBaseline": medians["candidate"] / medians["baseline"],
            }
    finally:
        gc.enable()
    return results


def differential(models):
    result = {"samples": 0, "mismatches": []}
    for epochs in WORKLOADS.values():
        for ut in epochs:
            for body in BODIES:
                restored = models["restored"].position(body, ut)
                candidate = models["candidate"].position(body, ut)
                result["samples"] += 1
                if struct.pack("=3d", *restored) != struct.pack("=3d", *candidate):
                    result["mismatches"].append(
                        {"body": body, "ut": ut, "restored": restored, "candidate": candidate}
                    )
    result["bitwiseEqual"] = not result["mismatches"]
    return result


def swift_report(root, output, libraries):
    if sys.platform != "darwin":
        return {"skipped": "optimized public-Swift probe currently requires macOS"}
    module_map = root / "Sources/CLibAstronomy/module.modulemap"
    sources = sorted((root / "Sources/AstronomyKit").glob("*.swift"))
    probe = root / "Scripts/performance/swift-probe.swift"
    records = {}
    for name, library in libraries.items():
        executable = output / f"swift-{name}"
        command = [
            "xcrun", "swiftc", "-O", "-whole-module-optimization", "-I", str(module_map.parent),
            "-Xcc", f"-fmodule-map-file={module_map}", *map(str, sources), str(probe),
            library["path"], "-o", str(executable),
        ]
        subprocess.run(command, check=True)
        records[name] = {"compileCommand": command, "executableSHA256": sha256(executable),
                         "workloads": {workload: {"trialsSeconds": [], "checksums": []}
                                       for workload in WORKLOADS}}
    execution_order = {workload: [] for workload in WORKLOADS}
    names = list(records)
    for workload in WORKLOADS:
        for round_index in range(5):
            rotation = round_index % len(names)
            for name in names[rotation:] + names[:rotation]:
                execution_order[workload].append(name)
                executable = output / f"swift-{name}"
                output_text = subprocess.check_output(
                    [str(executable), workload, "1"], text=True)
                values = json.loads(output_text)[workload]
                if not all(math.isfinite(value)
                           for value in values["trialsSeconds"] + values["checksums"]):
                    raise RuntimeError(f"non-finite optimized Swift result for {name}")
                records[name]["workloads"][workload]["trialsSeconds"].extend(
                    values["trialsSeconds"])
                records[name]["workloads"][workload]["checksums"].extend(values["checksums"])
    for record in records.values():
        for values in record["workloads"].values():
            values["medianSeconds"] = statistics.median(values["trialsSeconds"])
    comparisons = {}
    for workload in WORKLOADS:
        if (records["candidate"]["workloads"][workload]["checksums"]
                != records["restored"]["workloads"][workload]["checksums"]):
            raise RuntimeError(f"candidate Swift checksums differ from restored for {workload}")
        medians = {name: records[name]["workloads"][workload]["medianSeconds"] for name in records}
        comparisons[workload] = {
            "medianSeconds": medians,
            "restoredSlowdownVsBaseline": medians["restored"] / medians["baseline"],
            "candidateSpeedupVsRestored": medians["restored"] / medians["candidate"],
            "candidateSlowdownVsBaseline": medians["candidate"] / medians["baseline"],
        }
    source_hashes = {str(path.relative_to(root)): sha256(path) for path in sources + [probe]}
    return {
        "api": "CelestialBody.geocentricPosition(at:)",
        "optimization": "swiftc -O -whole-module-optimization",
        "compiler": subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip(),
        "sourceFilesSHA256": source_hashes,
        "executionOrder": execution_order,
        "records": records,
        "comparisons": comparisons,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/performance")
    parser.add_argument("--skip-swift", action="store_true")
    args = parser.parse_args()
    root, output = args.root.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(root / "Scripts/accuracy"))
    from measure import Model
    subprocess.run([sys.executable, str(root / "Scripts/generate-models.py"), "--check"], check=True)
    sources = {}
    for name, revision in (("baseline", BASELINE), ("restored", RESTORED)):
        source = output / f"{name}-{revision[:7]}.c"
        source.write_bytes(subprocess.check_output(
            ["git", "show", f"{revision}:Sources/CLibAstronomy/astronomy.c"], cwd=root))
        sources[name] = source
    libraries = {
        "baseline": compile_c(root, output, "baseline", sources["baseline"]),
        "restored": compile_c(root, output, "restored", sources["restored"]),
        "candidate": compile_c(root, output, "candidate", root / "Sources/CLibAstronomy/astronomy.c"),
    }
    models = {name: Model(record["path"]) for name, record in libraries.items()}
    exact = differential(models)
    if not exact["bitwiseEqual"]:
        raise RuntimeError("candidate native samples differ bitwise from restored")
    report = {
        "schemaVersion": 1,
        "baselineRevision": BASELINE,
        "restoredRevision": RESTORED,
        "candidateRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "workload": {"bodies": BODIES, "positionsPerTrial": 1600, "trials": 5,
                     "coldStreamUT": "9000 + i*0.125", "hotSameEpochUT": 9000.0},
        "platform": platform.platform(), "machine": platform.machine(),
        "python": sys.version, "clang": subprocess.check_output(["clang", "--version"], text=True).splitlines()[0],
        "libraries": libraries,
        "native": native_report(models),
        "differential": exact,
        "harnessSHA256": {
            "Scripts/performance/benchmark.py": sha256(Path(__file__)),
            "Scripts/performance/swift-probe.swift": sha256(root / "Scripts/performance/swift-probe.swift"),
        },
    }
    if not args.skip_swift:
        report["swift"] = swift_report(root, output, libraries)
    report_path = output / "results.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
