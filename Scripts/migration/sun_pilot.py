#!/usr/bin/env python3
"""Compare the native Sun pilot with the frozen C source and archive measurements."""

import argparse
import gzip
import hashlib
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def load_module(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MEASURE = load_module("representation_measure", "Scripts/model-prototype/measure.py")


def differences(expected, actual):
    if expected.get("status") != actual.get("status"):
        return ["status"]
    if expected["status"] != "success":
        return []
    failures = []
    for field in ("ut", "tt", "fallback", "iterations", "fallbackEvaluations"):
        if actual.get(field) != expected[field]:
            failures.append(field)
    for field in ("x", "y", "z", "gx", "gy", "gz", "ra", "dec", "distance", "altitude"):
        reference, value = expected[field], actual.get(field)
        if type(value) not in (int, float) or not math.isfinite(value) or not math.isfinite(reference):
            failures.append(field)
            continue
        delta = abs(value - reference)
        if field == "ra":
            delta = abs((value - reference + 12) % 24 - 12)
            tolerance = 1e-8 / 15
        elif field in ("dec", "altitude"):
            tolerance = 1e-8
        else:
            tolerance = max(1e-12, abs(reference) * 1e-12)
        if delta > tolerance:
            failures.append(field)
    return failures


def corpus():
    cases = []

    def add(category, model, scale, value, lat=35.0, lon=-80.0, height=100.0, ut=None):
        cases.append({"category": category, "model": model, "scale": scale, "value": value,
                      "latitude": lat, "longitude": lon, "height": height,
                      "ut": value if ut is None else ut})

    for model in ("espenak-meeus", "jpl-horizons"):
        # Each segment start and the exclusive stop, including immediate binary64 neighbors.
        for seam in [-36524.5 + 8 * index for index in range(9177)] + [36889.5]:
            for value in (math.nextafter(seam, -math.inf), seam, math.nextafter(seam, math.inf)):
                add("seam", model, "pair", value)
        for year in (-500, 500, 1600, 1700, 1800, 1860, 1900, 1920, 1941, 1961, 1986, 2005, 2050, 2150):
            boundary = (year - 2000) * 365.24217 + 14
            for value in (math.nextafter(boundary, -math.inf), boundary, math.nextafter(boundary, math.inf)):
                add("delta-t", model, "ut", value)
        clamp = 17.0 * 365.24217
        for value in (math.nextafter(clamp, -math.inf), clamp, math.nextafter(clamp, math.inf)):
            add("delta-t", model, "ut", value)
        for epoch in (-1460999.99, -1000000, -36525, 36890, 1000000, 1460999.99):
            for lat, lon, height in ((-90, -180, -500), (90, 180, 8848), (0, 0, 0), (89.999999, 179.999999, 1e6)):
                add("observer-fallback", model, "ut", epoch, lat, lon, height)
        # The broad scan identifies stopping-count transitions; retain adjacent representable epochs too.
        for index in range(2000):
            epoch = -36500.0 + index * 36.7
            for value in (math.nextafter(epoch, -math.inf), epoch, math.nextafter(epoch, math.inf)):
                add("iteration-scan", model, "ut", value)
        for value in ("nan", "inf", "-inf", 1461001, -1461001):
            add("invalid", model, "pair", value, ut=0)
        for field in ("latitude", "longitude", "height"):
            for value in ("nan", "inf", "-inf"):
                add("invalid", model, "ut", 0)
                cases[-1][field] = value
        add("invalid", model, "pair", 0, ut="nan")
        for value in (-0.0, 0.0):
            add("signed-zero", model, "ut", value)
    return cases


def input_text(cases):
    return "".join(" ".join(str(item[key]) for key in ("model", "scale", "value", "latitude", "longitude", "height", "ut")) + "\n" for item in cases)


def write_gzip(path, data):
    path.write_bytes(gzip.compress(data, mtime=0))


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n")


def source_hashes():
    hashes = MEASURE.prototype_inputs(ROOT)
    for relative in ("Scripts/migration/sun_pilot.py", "Scripts/migration/test_sun_pilot.py",
                     "Documentation/Migration/SunPilotProtocol.md", ".github/workflows/sun-pilot.yml"):
        path = ROOT / relative
        if path.exists():
            hashes[relative] = MEASURE.sha256(path)
    return dict(sorted(hashes.items()))


def prepare_package(destination):
    MEASURE.copy_workspace(destination)
    shutil.copy2(ROOT / "Tools/Migration/SunPilotPackage/Package.swift", destination / "Package.swift")
    (destination / ".model-prototype").unlink()
    return json.loads(MEASURE.logged_output(["swift", "package", "dump-package"], destination))


def build_oracle(output):
    lock_path = ROOT / "Tools/Migration/Oracle/oracle-lock.json"
    lock = json.loads(lock_path.read_text())
    compiler = os.environ.get("CC") or shutil.which("clang") or shutil.which("cc")
    if not compiler:
        raise RuntimeError("C compiler unavailable")
    with tempfile.TemporaryDirectory(prefix="sun-pilot-oracle-") as temporary:
        directory = Path(temporary)
        archive = subprocess.check_output(["git", "archive", lock["baselineRevision"], *lock["files"]], cwd=ROOT)
        with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
            stream.extractall(directory, filter="data")
        for relative, digest in lock["files"].items():
            if MEASURE.sha256(directory / relative) != digest:
                raise RuntimeError(f"frozen oracle mismatch: {relative}")
        driver = ROOT / "Tools/Migration/SunPilotOracle/main.c"
        engine = directory / "Sources/CLibAstronomy"
        command = [compiler, *lock["build"]["flags"], "-I", str(engine), "-I", str(engine / "include"), str(driver), "-lm", "-pthread", "-o", str(output)]
        MEASURE.logged_run(command, ROOT)
    return {"revision": lock["baselineRevision"], "lockSHA256": MEASURE.sha256(lock_path),
            "driverSHA256": MEASURE.sha256(driver), "binarySHA256": MEASURE.sha256(output),
            "compiler": subprocess.check_output([compiler, "--version"], text=True).strip(), "flags": lock["build"]["flags"]}


def compare(cases, expected, actual):
    if len(expected) != len(cases) or len(actual) != len(cases):
        raise RuntimeError("comparison sample count differs")
    failures = []
    maxima = {field: 0.0 for field in ("x", "y", "z", "gx", "gy", "gz", "ra", "dec", "distance", "altitude")}
    counts = {}
    nonzero = dict.fromkeys(maxima, 0)
    for index, (case, reference, candidate) in enumerate(zip(cases, expected, actual)):
        fields = differences(reference, candidate)
        if fields:
            failures.append({"index": index, "category": case["category"], "fields": fields})
        counts[reference["status"]] = counts.get(reference["status"], 0) + 1
        if reference["status"] == candidate["status"] == "success":
            for field in maxima:
                delta = abs(candidate[field] - reference[field])
                if field == "ra":
                    delta = abs((candidate[field] - reference[field] + 12) % 24 - 12)
                maxima[field] = max(maxima[field], delta)
                nonzero[field] += delta != 0
    flips = [index for index in range(1, len(cases)) if cases[index]["category"] == cases[index-1]["category"] == "iteration-scan"
             and expected[index].get("iterations") != expected[index-1].get("iterations")]
    return {"passed": not failures, "count": len(cases), "failures": failures, "maxAbsoluteDifferences": maxima,
            "statuses": counts, "nonzeroDifferenceCounts": nonzero,
            "differenceClassification": "Exact time/status/branch diagnostics; finite coordinate differences are budgeted regression rounding, not independent accuracy evidence.", "fallbackSamples": sum(bool(row.get("fallback")) for row in expected),
            "fallbackEvaluations": sum(row.get("fallbackEvaluations", 0) for row in expected),
            "iterationCounts": sorted(set(row["iterations"] for row in expected if "iterations" in row)),
            "iterationTransitionIndexes": flips}


def batch(command, text, destination):
    process = subprocess.run(command, input=text, capture_output=True, text=True, cwd=ROOT)
    MEASURE.ACTIVE_LOG.save(command, ROOT, "See compressed JSONL output.", process.stderr, process.returncode)
    write_gzip(destination, process.stdout.encode())
    process.check_returncode()
    return [json.loads(line) for line in process.stdout.splitlines()]


def timed_build(package, scratch, configuration):
    with tempfile.NamedTemporaryFile() as stream:
        path = Path(stream.name)
        command = [*MEASURE.time_arguments(path), "swift", "build", "-c", configuration,
                   "--product", "AstronomySunPilotRunner", "--scratch-path", str(scratch)]
        start = time.perf_counter()
        process = subprocess.run(command, capture_output=True, text=True, cwd=package)
        elapsed = time.perf_counter() - start
        MEASURE.ACTIVE_LOG.save(command, package, process.stdout, process.stderr, process.returncode, path.read_text(), elapsed)
        process.check_returncode()
        return elapsed, MEASURE.parse_rss(path)


def builds(package, configuration, trials):
    scratch = package / f".build/sun-pilot-{configuration}"
    timed_build(package, scratch, configuration)
    clean, incremental, clean_rss, incremental_rss = [], [], [], []
    for _ in range(trials):
        shutil.rmtree(scratch)
        elapsed, rss = timed_build(package, scratch, configuration)
        clean.append(elapsed)
        clean_rss.append(rss)
    source = package / "Sources/AstronomyModelPrototype/SunPilot.swift"
    stamp = source.stat()
    try:
        for index in range(trials):
            future = time.time() + index + 1
            os.utime(source, (future, future))
            elapsed, rss = timed_build(package, scratch, configuration)
            incremental.append(elapsed)
            incremental_rss.append(rss)
    finally:
        os.utime(source, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
    binary_directory = MEASURE.logged_output(["swift", "build", "-c", configuration, "--show-bin-path", "--scratch-path", str(scratch)], package)
    return {"cleanSeconds": clean, "incrementalSeconds": incremental,
            "cleanPeakResidentBytes": clean_rss, "incrementalPeakResidentBytes": incremental_rss}, Path(binary_directory) / "AstronomySunPilotRunner"


def runtime(binary, count):
    samples = []
    for _ in range(count):
        with tempfile.NamedTemporaryFile() as stream:
            path = Path(stream.name)
            command = [*MEASURE.time_arguments(path), str(binary), "--performance"]
            process = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
            MEASURE.ACTIVE_LOG.save(command, ROOT, process.stdout, process.stderr, process.returncode, path.read_text())
            process.check_returncode()
            samples.append({"workloads": json.loads(process.stdout), "peakResidentBytes": MEASURE.parse_rss(path)})
    return samples


def inspect_compensation(output):
    source = ROOT / "Sources/AstronomyModelPrototype/EarthPilot.swift"
    text = source.read_text()
    start = text.index("    static func compensatedAdd(")
    body_start = text.index("{", start)
    depth, stop = 1, body_start + 1
    while depth:
        depth += (text[stop] == "{") - (text[stop] == "}")
        stop += 1
    function = text[start:stop].replace("static func compensatedAdd", "public func compensatedAdd", 1)
    probe = output / "compensation.swift"
    probe.write_text(function + "\n")
    ir = output / "compensation.ll"
    command = ["swiftc", "-O", "-parse-as-library", "-emit-ir", str(probe), "-o", str(ir)]
    MEASURE.logged_run(command, ROOT)
    contents = ir.read_text()
    import re
    unsafe = re.findall(r"\b(?:fadd|fsub|fmul)\s+(?:fast|reassoc|contract)\b|llvm\.fmuladd|llvm\.fma\.", contents)
    if unsafe:
        raise RuntimeError("compensation code generation permits reassociation or contraction")
    return {"sourceSHA256": MEASURE.sha256(source), "extractedSourceSHA256": MEASURE.sha256(probe),
            "irSHA256": MEASURE.sha256(ir), "reassociationOrContractionFound": False,
            "scope": "Extracted unchanged compensated-add expression under -O; the whole engine is not certified."}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--test", action="store_true", help="Run focused Debug and Release tests in the isolated development package")
    parser.add_argument("--quick", action="store_true", help="Diagnostic corpus/build trials; never qualifies the pilot")
    arguments = parser.parse_args()
    if arguments.test:
        with tempfile.TemporaryDirectory(prefix="sun-pilot-tests-") as temporary:
            package = Path(temporary) / "package"
            prepare_package(package)
            for configuration in ("debug", "release"):
                subprocess.run(["swift", "test", "-c", configuration, "--filter", "SunPilotTests|ModelDataTests"], cwd=package, check=True)
        return
    if arguments.output is None:
        parser.error("--output is required for measurement")
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    MEASURE.ACTIVE_LOG = MEASURE.CommandLog(output / "logs")
    inputs = source_hashes()
    cases = corpus()
    if arguments.quick:
        cases = cases[:12] + [item for item in cases if item["category"] != "seam"][:200]
    text = input_text(cases)
    write_gzip(output / "inputs.json.gz", json.dumps(cases, sort_keys=True, allow_nan=False).encode())
    record = {"schemaVersion": 1, "status": "incomplete", "qualified": False, "diagnostic": arguments.quick,
              "candidateRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "candidateDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
              "sourceSHA256": inputs,
              "environment": {"platform": platform.platform(), "machine": platform.machine(), "system": platform.system(),
                              "swift": subprocess.check_output(["swift", "--version"], text=True).strip()},
              "protocolSHA256": MEASURE.sha256(ROOT / "Documentation/Migration/SunPilotProtocol.md")}
    write_json(output / "report.json", record)
    record["compensationCodeGeneration"] = inspect_compensation(output)
    record["oracle"] = build_oracle(output / "sun-pilot-oracle")
    expected = batch([str(output / "sun-pilot-oracle")], text, output / "oracle.jsonl.gz")
    record["oracleRuntime"] = runtime(output / "sun-pilot-oracle", 1 if arguments.quick else 5)
    record["configurations"] = {}
    with tempfile.TemporaryDirectory(prefix="sun-pilot-package-") as temporary:
        package = Path(temporary) / "package"
        evaluated_manifest = prepare_package(package)
        record["effectivePackage"] = {"manifestSHA256": MEASURE.sha256(package / "Package.swift"),
                                      "evaluatedManifest": evaluated_manifest,
                                      "evaluatedManifestSHA256": hashlib.sha256(json.dumps(evaluated_manifest, sort_keys=True).encode()).hexdigest(),
                                      "developmentManifest": "Tools/Migration/SunPilotPackage/Package.swift"}
        for configuration in ("debug", "release"):
            print(f"Measuring {configuration}", flush=True)
            build_record, binary = builds(package, configuration, 1 if arguments.quick else 3)
            actual = batch([str(binary)], text, output / f"{configuration}.jsonl.gz")
            result = compare(cases, expected, actual)
            # Perturb the full-series evaluator, then require its fallback outputs to fail the unchanged numerical budget.
            fallback_cases = [case for case, row in zip(cases, expected) if row.get("fallback")][:8]
            fallback_expected = [row for row in expected if row.get("fallback")][:8]
            perturbed = batch([str(binary), "--perturb-fallback"], input_text(fallback_cases), output / f"{configuration}-perturbed.jsonl.gz")
            control = compare(fallback_cases, fallback_expected, perturbed)
            if not fallback_cases or control["passed"]:
                raise RuntimeError("intentional fallback perturbation was not detected")
            values = runtime(binary, 1 if arguments.quick else 5)
            build_record.update({"comparison": result, "perturbationDetected": True, "perturbationFailures": control["failures"], "runtime": values,
                                 "binarySHA256": MEASURE.sha256(binary)})
            stripped = output / f"sun-pilot-{configuration}-stripped"
            shutil.copy2(binary, stripped)
            strip = ["strip", "-S", "-x", str(stripped)] if platform.system() == "Darwin" else ["strip", "--strip-all", str(stripped)]
            MEASURE.logged_run(strip, ROOT)
            build_record["strippedBinaryBytes"] = stripped.stat().st_size
            record["configurations"][configuration] = build_record
            write_json(output / "report.json", record)
    MEASURE.require_unchanged_snapshot(inputs, source_hashes())
    frozen = json.loads((ROOT / "Documentation/Migration/performance-baseline.json").read_text())
    release = record["configurations"]["release"]
    observations = {"cleanBuildSeconds": max(release["cleanSeconds"]), "incrementalBuildSeconds": max(release["incrementalSeconds"]),
                    "strippedBinaryBytes": release["strippedBinaryBytes"],
                    "peakResidentBytes": max(sample["peakResidentBytes"] for sample in release["runtime"])}
    exceeded = [key for key, value in observations.items() if value > frozen["budgets"][key]]
    record["fixedBudgetObservations"] = {"baselineSHA256": MEASURE.sha256(ROOT / "Documentation/Migration/performance-baseline.json"),
                                         "budgets": frozen["budgets"], "observations": observations, "exceeded": exceeded}
    record["unmetGates"] = ["Native Sun-only workloads cannot execute the frozen mixed-workload latency/throughput protocol.",
                            "Independent review and both platform receipts are required before an issue closeout."]
    if exceeded:
        record["unmetGates"].append("Measured observations exceed fixed budgets: " + ", ".join(exceeded))
    if arguments.quick:
        record["unmetGates"].append("Diagnostic mode omits the full corpus and trial counts.")
    record["status"] = "complete-evidence"
    record["numericalPassed"] = all(item["comparison"]["passed"] for item in record["configurations"].values())
    record["commandLogs"] = MEASURE.ACTIVE_LOG.receipt()
    record["artifactSHA256"] = {path.name: MEASURE.sha256(path) for path in output.iterdir() if path.is_file() and path.name != "report.json"}
    write_json(output / "report.json", record)
    print(json.dumps({"numericalPassed": record["numericalPassed"], "qualified": False, "unmetGates": record["unmetGates"]}, sort_keys=True), flush=True)
    if not record["numericalPassed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
