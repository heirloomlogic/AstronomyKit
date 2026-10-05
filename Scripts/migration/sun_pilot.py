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
import re
import select
import shutil
import signal
import statistics
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
RSS_STAGES = (
    "startup", "serialization", "polynomialEarth", "fallbackEarth",
    "polynomialCache", "fallbackCache", "firstAccess", "freshPolynomial",
    "repeatedPolynomial", "freshFallback", "repeatedFallback", "aggregate",
)
RSS_STAGE_DESCRIPTIONS = {
    "startup": "Enter the executable and emit a scalar without model access.",
    "serialization": "Encode and emit a fixed empty workload without model access.",
    "polynomialEarth": "Evaluate one Earth polynomial position without observer or orientation work.",
    "fallbackEarth": "Evaluate one complete Earth VSOP position, including lazy triplet materialization.",
    "polynomialCache": "Evaluate the same polynomial Sun observation twice with one caller-owned evaluator.",
    "fallbackCache": "Evaluate the same fallback Sun observation twice with one caller-owned evaluator.",
    "firstAccess": "Run the existing one-operation first-access workload.",
    "freshPolynomial": "Run the existing 200-epoch fresh polynomial workload.",
    "repeatedPolynomial": "Run the existing warm-up plus 200 repeated polynomial observations.",
    "freshFallback": "Run the existing 200-epoch fresh fallback workload.",
    "repeatedFallback": "Run the existing warm-up plus 200 repeated fallback observations.",
    "aggregate": "Run all five existing workloads and encode their timing report.",
}
AGGREGATE_MODES = (
    "firstAccess", "freshPolynomial", "repeatedPolynomial", "freshFallback", "repeatedFallback",
)
AGGREGATE_CHECKPOINTS = ("beforeWork", *AGGREGATE_MODES)
AGGREGATE_OPERATIONS = {mode: 1 if mode == "firstAccess" else 200 for mode in AGGREGATE_MODES}
AGGREGATE_TRIALS = 5
AGGREGATE_TIMEOUT_SECONDS = 10


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
                     "Documentation/Migration/SunPilotProtocol.md", "Documentation/Migration/SunPilotAggregateRSSProtocol.md",
                     ".github/workflows/sun-pilot.yml"):
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


def measured_process(binary, arguments):
    with tempfile.NamedTemporaryFile() as stream:
        path = Path(stream.name)
        command = [*MEASURE.time_arguments(path), str(binary), *arguments]
        process = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
        MEASURE.ACTIVE_LOG.save(command, ROOT, process.stdout, process.stderr, process.returncode, path.read_text())
        process.check_returncode()
        return {"peakResidentBytes": MEASURE.parse_rss(path), "stdout": process.stdout}


def runtime(binary, count):
    samples = []
    for _ in range(count):
        measured = measured_process(binary, ["--performance"])
        samples.append({"workloads": json.loads(measured["stdout"]), "peakResidentBytes": measured["peakResidentBytes"]})
    return samples


def validate_rss_attribution(receipt, count):
    if tuple(receipt) != RSS_STAGES:
        raise ValueError("RSS stage inventory differs")
    for stage, samples in receipt.items():
        if len(samples) != count:
            raise ValueError(f"RSS stage {stage} requires {count} trials")
        for sample in samples:
            if type(sample.get("peakResidentBytes")) is not int or sample["peakResidentBytes"] <= 0:
                raise ValueError(f"RSS stage {stage} has invalid peak memory")
            if not sample.get("stdout"):
                raise ValueError(f"RSS stage {stage} has no checksum output")
    return receipt


def validate_matched_earth_stages(candidate, oracle, count):
    for stage in ("polynomialEarth", "fallbackEarth"):
        candidate_samples = candidate.get(stage, [])
        oracle_samples = oracle.get(stage, [])
        if len(candidate_samples) != count or len(oracle_samples) != count:
            raise ValueError(f"matched Earth stage {stage} requires {count} trials")
        for candidate_sample, oracle_sample in zip(candidate_samples, oracle_samples):
            try:
                candidate_checksum = float(candidate_sample["stdout"])
                oracle_checksum = float(oracle_sample["stdout"])
            except (KeyError, TypeError, ValueError) as error:
                raise ValueError(f"matched Earth stage {stage} has an invalid checksum") from error
            if not math.isfinite(candidate_checksum) or candidate_checksum != oracle_checksum:
                raise ValueError(f"matched Earth stage {stage} checksum differs from the oracle")
    return candidate


def rss_attribution(binary, count):
    receipt = {
        stage: [measured_process(binary, ["--rss-stage", stage]) for _ in range(count)]
        for stage in RSS_STAGES
    }
    return validate_rss_attribution(receipt, count)


def validate_workload(mode, workload):
    if not isinstance(workload, dict) or set(workload) != {"operations", "elapsedNanoseconds", "checksum"}:
        raise ValueError(f"aggregate checkpoint {mode} has malformed workload data")
    if workload["operations"] != AGGREGATE_OPERATIONS[mode]:
        raise ValueError(f"aggregate checkpoint {mode} changed its operation count")
    if type(workload["elapsedNanoseconds"]) is not int or workload["elapsedNanoseconds"] < 0:
        raise ValueError(f"aggregate checkpoint {mode} has invalid elapsed time")
    if type(workload["checksum"]) not in (int, float) or not math.isfinite(workload["checksum"]):
        raise ValueError(f"aggregate checkpoint {mode} has invalid checksum")
    return workload


def validate_aggregate_checkpoint_trial(trial):
    if type(trial.get("externalPeakResidentBytes")) is not int or trial["externalPeakResidentBytes"] <= 0:
        raise ValueError("aggregate checkpoint trial has invalid external peak RSS")
    checkpoints = trial.get("checkpoints")
    if not isinstance(checkpoints, list) or tuple(row.get("checkpoint") for row in checkpoints) != AGGREGATE_CHECKPOINTS:
        raise ValueError("aggregate checkpoint sequence differs")
    workloads = trial.get("workloads")
    if not isinstance(workloads, dict) or set(workloads) != set(AGGREGATE_MODES):
        raise ValueError("aggregate checkpoint final workload inventory differs")
    for index, row in enumerate(checkpoints):
        mapping = row.get("mappingRSSBytes")
        if not isinstance(mapping, dict) or any(type(value) is not int or value < 0 for value in mapping.values()):
            raise ValueError(f"aggregate checkpoint {row.get('checkpoint')} has invalid mapping RSS")
        if index == 0:
            if "workload" in row:
                raise ValueError("aggregate before-work checkpoint unexpectedly contains a workload")
            continue
        mode = AGGREGATE_MODES[index - 1]
        checkpoint_workload = validate_workload(mode, row.get("workload"))
        final_workload = validate_workload(mode, workloads.get(mode))
        if checkpoint_workload != final_workload:
            raise ValueError(f"aggregate checkpoint {mode} differs from final output")
    return trial


def mapping_class(path, binary):
    if not path:
        return "anonymous"
    if path == "[heap]":
        return "heap"
    if path.startswith("[stack"):
        return "stack"
    if path.startswith("["):
        return "kernelSpecial"
    cleaned = path.removesuffix(" (deleted)")
    if Path(cleaned) == binary:
        return "executable"
    if "/swift/" in cleaned or Path(cleaned).name.startswith("libswift"):
        return "swiftRuntime"
    if ".so" in Path(cleaned).name:
        return "sharedLibrary"
    return "otherFileBacked"


def classify_smaps(contents, binary):
    totals = {}
    current = None
    for line in contents.splitlines():
        if re.match(r"^[0-9a-f]+-[0-9a-f]+\s", line):
            fields = line.split(maxsplit=5)
            current = mapping_class(fields[5] if len(fields) == 6 else "", binary)
        elif current is not None and line.startswith("Rss:"):
            fields = line.split()
            if len(fields) != 3 or fields[2] != "kB":
                raise ValueError("aggregate smaps RSS row is malformed")
            totals[current] = totals.get(current, 0) + int(fields[1]) * 1024
    if not totals:
        raise ValueError("aggregate smaps snapshot has no RSS rows")
    return dict(sorted(totals.items()))


def parse_status_memory(contents):
    values = {}
    for line in contents.splitlines():
        key, separator, remainder = line.partition(":")
        if separator and key in {"VmRSS", "VmHWM"}:
            fields = remainder.split()
            if len(fields) != 2 or fields[1] != "kB":
                raise ValueError(f"aggregate status {key} row is malformed")
            values[key + "Bytes"] = int(fields[0]) * 1024
    if set(values) != {"VmRSSBytes", "VmHWMBytes"}:
        raise ValueError("aggregate status snapshot lacks VmRSS or VmHWM")
    return values


def read_process_line(descriptor, timeout_seconds):
    deadline = time.monotonic() + timeout_seconds
    data = bytearray()
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([descriptor], [], [], max(0, remaining))[0]:
            raise TimeoutError("aggregate checkpoint timed out")
        byte = os.read(descriptor, 1)
        if not byte:
            raise RuntimeError("aggregate checkpoint process closed stdout")
        if byte == b"\n":
            try:
                return data.decode()
            except UnicodeDecodeError as error:
                raise ValueError("aggregate checkpoint is not UTF-8") from error
        data.extend(byte)
        if len(data) > 1_000_000:
            raise ValueError("aggregate checkpoint line is too large")


def cleanup_process_group(process):
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def discover_child_pid(process, timeout_seconds):
    path = Path(f"/proc/{process.pid}/task/{process.pid}/children")
    deadline = time.monotonic() + timeout_seconds
    last = ""
    while time.monotonic() < deadline and process.poll() is None:
        try:
            last = path.read_text().strip()
        except OSError:
            last = ""
        children = last.split()
        if len(children) == 1:
            return int(children[0])
        if len(children) > 1:
            raise RuntimeError(f"aggregate timing wrapper has multiple children: {last}")
        time.sleep(0.01)
    raise RuntimeError(f"aggregate timing wrapper child was not observed: {last}")


def is_blocked_stdin_read(contents, machine):
    syscall = {"x86_64": 0, "aarch64": 63, "arm64": 63}.get(machine)
    fields = contents.split()
    if syscall is None or len(fields) < 2 or fields[0] == "running":
        return False
    try:
        return int(fields[0], 0) == syscall and int(fields[1], 0) == 0
    except ValueError:
        return False


def observe_blocked_checkpoint(pid, timeout_seconds):
    path = Path(f"/proc/{pid}/syscall")
    deadline = time.monotonic() + timeout_seconds
    last = "unavailable"
    while time.monotonic() < deadline:
        try:
            last = path.read_text().strip()
        except OSError as error:
            last = f"{type(error).__name__}: {error}"
        if is_blocked_stdin_read(last, platform.machine()):
            return {"mechanism": "proc-syscall-read-stdin", "observedSyscall": last}
        time.sleep(0.01)
    raise TimeoutError(f"aggregate checkpoint did not block on stdin: {last}")


def retain_proc_checkpoint(directory, checkpoint, pid, binary):
    readiness = observe_blocked_checkpoint(pid, AGGREGATE_TIMEOUT_SECONDS)
    retained = {}
    contents = {}
    for name in ("status", "smaps", "maps"):
        text = Path(f"/proc/{pid}/{name}").read_text()
        path = directory / f"{checkpoint}.{name}.txt"
        path.write_text(text)
        contents[name] = text
        retained[name] = {"path": path.name, "sha256": MEASURE.sha256(path)}
    return {
        "checkpoint": checkpoint,
        "mappingRSSBytes": classify_smaps(contents["smaps"], binary.resolve()),
        "processStatus": parse_status_memory(contents["status"]),
        "readiness": readiness,
        "retained": retained,
    }


def aggregate_checkpoint_trial(binary, output, label, trial_index):
    if platform.system() != "Linux":
        raise RuntimeError("aggregate checkpoint measurement requires Linux")
    directory = output / "aggregate-checkpoints" / label / f"trial-{trial_index}"
    directory.mkdir(parents=True, exist_ok=False)
    with tempfile.NamedTemporaryFile() as stream:
        time_path = Path(stream.name)
        command = [*MEASURE.time_arguments(time_path), str(binary), "--rss-aggregate-checkpoints"]
        process = subprocess.Popen(
            command, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            child_pid = discover_child_pid(process, AGGREGATE_TIMEOUT_SECONDS)
            checkpoints = []
            for expected in AGGREGATE_CHECKPOINTS:
                try:
                    payload = json.loads(read_process_line(process.stdout.fileno(), AGGREGATE_TIMEOUT_SECONDS))
                except json.JSONDecodeError as error:
                    raise ValueError("aggregate checkpoint emitted malformed JSON") from error
                if payload.get("checkpoint") != expected or set(payload) - {"checkpoint", "workload"}:
                    raise ValueError(f"aggregate checkpoint differs: expected {expected}")
                snapshot = retain_proc_checkpoint(directory, expected, child_pid, binary)
                if expected == "beforeWork":
                    if "workload" in payload:
                        raise ValueError("aggregate before-work checkpoint contains a workload")
                else:
                    snapshot["workload"] = validate_workload(expected, payload.get("workload"))
                checkpoints.append(snapshot)
                process.stdin.write(b"continue\n")
                process.stdin.flush()
            try:
                workloads = json.loads(read_process_line(process.stdout.fileno(), AGGREGATE_TIMEOUT_SECONDS))
            except json.JSONDecodeError as error:
                raise ValueError("aggregate checkpoint final output is malformed JSON") from error
            process.stdin.close()
            process.wait(timeout=AGGREGATE_TIMEOUT_SECONDS)
            stderr = process.stderr.read().decode(errors="replace")
            if process.returncode:
                raise subprocess.CalledProcessError(process.returncode, command, "", stderr)
            trial = {
                "checkpoints": checkpoints,
                "externalPeakResidentBytes": MEASURE.parse_rss(time_path),
                "targetPID": child_pid,
                "workloads": workloads,
            }
            validate_aggregate_checkpoint_trial(trial)
            MEASURE.ACTIVE_LOG.save(command, ROOT, "Checkpoint JSON and proc snapshots retained separately.", stderr, process.returncode, time_path.read_text())
            return trial
        except Exception:
            cleanup_process_group(process)
            raise


def summarize_aggregate_checkpoints(trials):
    if len(trials) != AGGREGATE_TRIALS:
        raise ValueError("aggregate checkpoint campaign requires five trials")
    for trial in trials:
        validate_aggregate_checkpoint_trial(trial)
    stage_summaries = {}
    growth = {}
    for index, checkpoint in enumerate(AGGREGATE_CHECKPOINTS):
        classes = sorted({name for trial in trials for name in trial["checkpoints"][index]["mappingRSSBytes"]})
        stage_summaries[checkpoint] = {}
        for name in classes:
            values = [trial["checkpoints"][index]["mappingRSSBytes"].get(name, 0) for trial in trials]
            stage_summaries[checkpoint][name] = {
                "minimumBytes": min(values), "medianBytes": int(statistics.median(values)), "maximumBytes": max(values),
            }
        if index:
            previous_classes = {name for trial in trials for name in trial["checkpoints"][index - 1]["mappingRSSBytes"]}
            for name in sorted(set(classes) | previous_classes):
                deltas = [
                    trial["checkpoints"][index]["mappingRSSBytes"].get(name, 0)
                    - trial["checkpoints"][index - 1]["mappingRSSBytes"].get(name, 0)
                    for trial in trials
                ]
                if min(deltas) > 0:
                    growth.setdefault(checkpoint, {})[name] = {
                        "minimumBytes": min(deltas), "medianBytes": int(statistics.median(deltas)), "maximumBytes": max(deltas),
                    }
    peaks = [trial["externalPeakResidentBytes"] for trial in trials]
    return {
        "externalPeakResidentBytes": {"minimum": min(peaks), "median": int(statistics.median(peaks)), "maximum": max(peaks)},
        "mappingRSSByCheckpoint": stage_summaries,
        "reproduciblePositiveGrowth": growth,
        "removableOwnerEstablished": False,
        "causalLimit": "Checkpoint instrumentation and mapping classes show residency correlation, not allocator ownership, additive cost, or removability.",
    }


def validate_checkpoint_workloads(campaign, uninstrumented):
    trials = campaign.get("trials", [])
    if len(trials) != AGGREGATE_TRIALS or len(uninstrumented) != AGGREGATE_TRIALS:
        raise ValueError("aggregate checkpoint workload binding requires five matched trials")
    for trial in trials:
        validate_aggregate_checkpoint_trial(trial)
    for mode in AGGREGATE_MODES:
        baseline = uninstrumented[0].get("workloads", {}).get(mode, {})
        validate_workload(mode, baseline)
        expected = {"operations": baseline["operations"], "checksum": baseline["checksum"]}
        samples = uninstrumented + [{"workloads": trial["workloads"]} for trial in trials]
        for sample in samples:
            workload = validate_workload(mode, sample.get("workloads", {}).get(mode))
            if {"operations": workload["operations"], "checksum": workload["checksum"]} != expected:
                raise ValueError(f"aggregate checkpoint workload {mode} differs from the uninstrumented run")
    return {"modeOrder": list(AGGREGATE_MODES), "operationCounts": AGGREGATE_OPERATIONS, "checksumsMatchUninstrumented": True}


def aggregate_checkpoint_campaign(binary, output, label):
    trials = [aggregate_checkpoint_trial(binary, output, label, index) for index in range(1, AGGREGATE_TRIALS + 1)]
    return {"trials": trials, "summary": summarize_aggregate_checkpoints(trials)}


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


def verify_output_delivery(binary):
    command = [sys.executable, "-m", "unittest", "Scripts.migration.test_sun_pilot.RunnerOutputTests", "-v"]
    environment = dict(os.environ, SUN_PILOT_RUNNER=str(binary))
    result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True)
    if MEASURE.ACTIVE_LOG:
        MEASURE.ACTIVE_LOG.save(command, ROOT, result.stdout, result.stderr, result.returncode)
    if result.returncode:
        raise RuntimeError("runner output delivery regressions failed:\n" + result.stderr)
    return {"passed": True, "regressionTests": 4, "binarySHA256": MEASURE.sha256(binary)}


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
                binary_directory = Path(MEASURE.logged_output(["swift", "build", "-c", configuration, "--show-bin-path"], package))
                verify_output_delivery(binary_directory / "AstronomySunPilotRunner")
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
              "protocolSHA256": MEASURE.sha256(ROOT / "Documentation/Migration/SunPilotProtocol.md"),
              "aggregateRSSProtocolSHA256": MEASURE.sha256(ROOT / "Documentation/Migration/SunPilotAggregateRSSProtocol.md")}
    write_json(output / "report.json", record)
    record["compensationCodeGeneration"] = inspect_compensation(output)
    record["oracle"] = build_oracle(output / "sun-pilot-oracle")
    expected = batch([str(output / "sun-pilot-oracle")], text, output / "oracle.jsonl.gz")
    runtime_trials = 1 if arguments.quick else 5
    record["oracleRuntime"] = runtime(output / "sun-pilot-oracle", runtime_trials)
    record["rssAttribution"] = {
        "schemaVersion": 1, "freshProcessPerStage": True,
        "stageSemantics": RSS_STAGE_DESCRIPTIONS,
        "oracle": rss_attribution(output / "sun-pilot-oracle", runtime_trials),
    }
    aggregate_investigation = platform.system() == "Linux" and not arguments.quick
    if aggregate_investigation:
        record["aggregateCheckpointInvestigation"] = {
            "schemaVersion": 1,
            "status": "running",
            "instrumentedDiagnostic": True,
            "separateFromUninstrumentedFixedBudgetGate": True,
            "trialCountPerBinary": AGGREGATE_TRIALS,
            "checkpointOrder": list(AGGREGATE_CHECKPOINTS),
            "modeOrder": list(AGGREGATE_MODES),
            "operationCounts": AGGREGATE_OPERATIONS,
            "fixedCeilingBytes": json.loads((ROOT / "Documentation/Migration/performance-baseline.json").read_text())["budgets"]["peakResidentBytes"],
            "oracle": aggregate_checkpoint_campaign(output / "sun-pilot-oracle", output, "oracle"),
        }
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
            delivery = verify_output_delivery(binary)
            actual = batch([str(binary)], text, output / f"{configuration}.jsonl.gz")
            result = compare(cases, expected, actual)
            # Perturb the full-series evaluator, then require its fallback outputs to fail the unchanged numerical budget.
            fallback_cases = [case for case, row in zip(cases, expected) if row.get("fallback")][:8]
            fallback_expected = [row for row in expected if row.get("fallback")][:8]
            perturbed = batch([str(binary), "--perturb-fallback"], input_text(fallback_cases), output / f"{configuration}-perturbed.jsonl.gz")
            control = compare(fallback_cases, fallback_expected, perturbed)
            if not fallback_cases or control["passed"]:
                raise RuntimeError("intentional fallback perturbation was not detected")
            values = runtime(binary, runtime_trials)
            stage_values = rss_attribution(binary, runtime_trials)
            validate_matched_earth_stages(stage_values, record["rssAttribution"]["oracle"], runtime_trials)
            build_record.update({"outputDelivery": delivery, "comparison": result, "perturbationDetected": True, "perturbationFailures": control["failures"], "runtime": values,
                                 "binarySHA256": MEASURE.sha256(binary)})
            record["rssAttribution"][configuration] = stage_values
            if configuration == "release" and aggregate_investigation:
                record["aggregateCheckpointInvestigation"]["candidate"] = aggregate_checkpoint_campaign(binary, output, "candidate")
            stripped = output / f"sun-pilot-{configuration}-stripped"
            shutil.copy2(binary, stripped)
            strip = ["strip", "-S", "-x", str(stripped)] if platform.system() == "Darwin" else ["strip", "--strip-all", str(stripped)]
            MEASURE.logged_run(strip, ROOT)
            build_record["strippedBinaryBytes"] = stripped.stat().st_size
            record["configurations"][configuration] = build_record
            write_json(output / "report.json", record)
    if aggregate_investigation:
        investigation = record["aggregateCheckpointInvestigation"]
        investigation["oracleWorkloadBinding"] = validate_checkpoint_workloads(investigation["oracle"], record["oracleRuntime"])
        investigation["candidateWorkloadBinding"] = validate_checkpoint_workloads(investigation["candidate"], record["configurations"]["release"]["runtime"])
        observed_growth = bool(investigation["candidate"]["summary"]["reproduciblePositiveGrowth"])
        investigation.update({
            "status": "complete-evidence",
            "assessment": {
                "reproducibleCandidateMappingClassGrowthObserved": observed_growth,
                "removableOwnerEstablished": False,
                "decision": "mapping-class-growth-observed-without-removable-owner" if observed_growth else "no-reproducible-mapping-class-growth-or-removable-owner",
                "limit": "The checkpoint protocol, pipes, timing wrapper, and proc snapshots can perturb residency. Only the separate uninstrumented aggregate trials determine the fixed memory gate.",
            },
        })
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
