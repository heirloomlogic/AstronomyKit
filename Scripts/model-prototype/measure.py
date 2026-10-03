#!/usr/bin/env python3
"""Measure the complete Swift model prototype without regenerating it."""

import re
import argparse
import hashlib
import importlib.util
import math
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
BASELINE = ROOT / "Documentation/Migration/performance-baseline.json"
OUTPUT = ROOT / "Documentation/Migration/model-prototype-evidence.json"
BUILD_TRIALS = 3
RUNTIME_TRIALS = 5
EXPECTED_FIRST_VALUE = 0xbfd0eee034b80b58
EXPECTED_WHOLE_MODEL_FNV64 = 0x0cd4295bc6da4d62


ACTIVE_LOG = None


class CommandLog:
    def __init__(self, directory):
        self.directory = directory.resolve()
        self.directory.mkdir(parents=True, exist_ok=False)
        self.entries = []

    def save(self, command, cwd, stdout, stderr, returncode, time_text=None, elapsed_seconds=None):
        number = len(self.entries) + 1
        files = {}
        for name, contents in (("stdout", stdout), ("stderr", stderr), ("time", time_text)):
            if contents is None:
                continue
            path = self.directory / f"{number:04d}-{name}.log"
            path.write_text(contents)
            files[name] = {"path": path.name, "sha256": sha256(path)}
        entry = {"command": [str(item) for item in command], "cwd": str(cwd), "returncode": returncode, "files": files}
        if elapsed_seconds is not None:
            entry["elapsedSeconds"] = elapsed_seconds
        self.entries.append(entry)
        write_record(self.directory / "commands.json", {"entries": self.entries})

    def receipt(self):
        return {"directory": self.directory.name, "manifestSHA256": sha256(self.directory / "commands.json"), "commandCount": len(self.entries)}


def logged_output(command, cwd):
    try:
        result = subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as error:
        if ACTIVE_LOG:
            ACTIVE_LOG.save(command, cwd, error.stdout or "", error.stderr or "", error.returncode)
        raise
    if ACTIVE_LOG:
        ACTIVE_LOG.save(command, cwd, result.stdout, result.stderr, result.returncode)
    return result.stdout.strip()


def logged_run(command, cwd):
    logged_output(command, cwd)


class BuildTimeout(TimeoutError):
    def __init__(self, elapsed_seconds, timeout_seconds):
        super().__init__(f"build did not finish within {timeout_seconds} seconds")
        self.elapsed_seconds = elapsed_seconds
        self.timeout_seconds = timeout_seconds


def evaluate_builds(measurements, budgets):
    summary = {
        "cleanReleaseSeconds": max(measurements["cleanReleaseSeconds"]),
        "incrementalReleaseSeconds": max(measurements["incrementalReleaseSeconds"]),
    }
    mapping = {"cleanReleaseSeconds": "cleanBuildSeconds", "incrementalReleaseSeconds": "incrementalBuildSeconds"}
    failures = [metric for metric, budget in mapping.items() if summary[metric] > budgets[budget]]
    return {"summary": summary, "failures": failures, "passed": not failures}


def validate_evidence(record):
    for configuration in ("Release", "Debug"):
        for mode in ("clean", "incremental"):
            metric = f"{mode}{configuration}Seconds"
            values = record.get(metric)
            if not isinstance(values, list) or len(values) != BUILD_TRIALS:
                raise ValueError(f"three {mode} {configuration} trials are required")
            if not all(type(value) in (int, float) and math.isfinite(value) and value > 0 for value in values):
                raise ValueError(f"{metric} contains invalid timings")
            memory = record.get(f"{mode}{configuration}PeakResidentBytes")
            if not isinstance(memory, list) or len(memory) != BUILD_TRIALS or not all(type(value) is int and value > 0 for value in memory):
                raise ValueError(f"{mode}{configuration}PeakResidentBytes requires three positive byte measurements")
    if re.fullmatch(r"[0-9a-f]{64}", record.get("workloadSHA256", "")) is None:
        raise ValueError("workload SHA-256 is invalid")
    for metric in ("firstAccessNanoseconds", "fullSweepNanoseconds", "firstAccessPeakResidentBytes", "fullSweepPeakResidentBytes"):
        values = record.get(metric)
        minimum = 0 if metric.endswith("Nanoseconds") else 1
        if not isinstance(values, list) or len(values) != RUNTIME_TRIALS or not all(type(value) is int and value >= minimum for value in values):
            raise ValueError(f"{metric} requires five valid measurements")
    if type(record.get("strippedExecutableBytes")) is not int or record["strippedExecutableBytes"] <= 0:
        raise ValueError("stripped executable size is invalid")
    return record


def write_checkpoint(path, phase, measurements, failure=None):
    has_failure = failure is not None
    record = {
        "schemaVersion": 2,
        "status": "incomplete" if has_failure else "running",
        "phase": phase,
        "measurements": measurements,
    }
    if has_failure:
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
    paths = [root / "Package.swift"]
    for directory in ("Sources", "Tests", "Tools", "Scripts/model-prototype"):
        paths.extend(path for path in (root / directory).rglob("*") if path.is_file() and "__pycache__" not in path.parts)
    paths.extend([root / "Scripts/migration/performance_baseline.py", root / "Scripts/generate-models.py"])
    paths.extend(path for path in (root / "Scripts/model-data").rglob("*") if path.is_file())
    paths.extend(path for path in (root / "Scripts/performance/polynomial").rglob("*") if path.is_file() and "__pycache__" not in path.parts)
    return {path.relative_to(root).as_posix(): sha256(path) for path in sorted(set(paths))}


def require_unchanged_snapshot(before, after):
    if before != after:
        raise RuntimeError("prototype inputs changed during measurement")


def copy_workspace(destination):
    destination.mkdir()
    shutil.copy2(ROOT / "Package.swift", destination / "Package.swift")
    shutil.copytree(ROOT / "Sources", destination / "Sources")
    shutil.copytree(ROOT / "Tests", destination / "Tests")
    shutil.copytree(ROOT / "Tools", destination / "Tools")
    (destination / ".model-prototype").touch()


def time_arguments(path):
    system = platform.system()
    if system not in ("Darwin", "Linux"):
        raise RuntimeError(f"unsupported time platform: {system}")
    return ["/usr/bin/time", "-l" if system == "Darwin" else "-v", "-o", str(path)]


def parse_rss(path, system=None):
    system = system or platform.system()
    for line in path.read_text().splitlines():
        if system == "Darwin" and "maximum resident set size" in line:
            value = int(line.split()[0])
            break
        if system == "Linux" and "Maximum resident set size (kbytes):" in line:
            value = int(line.rsplit(":", 1)[1].strip()) * 1024
            break
    else:
        raise RuntimeError("compiler RSS was not recorded")
    if value <= 0:
        raise RuntimeError("peak resident bytes must be positive")
    return value


def timed_build(package, scratch, configuration, timeout_seconds=None):
    command = ["swift", "build", "-c", configuration, "--product", "AstronomyModelPrototypeRunner", "--scratch-path", str(scratch)]
    with tempfile.NamedTemporaryFile(prefix="model-prototype-time-", delete=False) as stream:
        time_path = Path(stream.name)
    try:
        command = [*time_arguments(time_path), *command]
        started = time.perf_counter()
        output = tempfile.TemporaryFile(mode="w+t")
        process = subprocess.Popen(command, cwd=package, stdout=output, stderr=subprocess.STDOUT, start_new_session=timeout_seconds is not None)
        try:
            return_code = process.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            elapsed = time.perf_counter() - started
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise BuildTimeout(elapsed, timeout_seconds) from None
        elapsed = time.perf_counter() - started
        output.seek(0)
        text = output.read()
        output.close()
        if ACTIVE_LOG:
            ACTIVE_LOG.save(command, package, text, "", return_code, time_path.read_text(), elapsed)
        if return_code:
            raise subprocess.CalledProcessError(return_code, command)
        return elapsed, parse_rss(time_path)
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
            checkpoint(f"{configuration}-clean-{len(clean_seconds)}", {f"clean{configuration.title()}Seconds": clean_seconds, f"clean{configuration.title()}PeakResidentBytes": clean_rss})
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
                checkpoint(f"{configuration}-incremental-{len(incremental_seconds)}", {f"clean{configuration.title()}Seconds": clean_seconds, f"incremental{configuration.title()}Seconds": incremental_seconds, f"clean{configuration.title()}PeakResidentBytes": clean_rss, f"incremental{configuration.title()}PeakResidentBytes": incremental_rss})
    finally:
        os.utime(source, ns=(original.st_atime_ns, original.st_mtime_ns))
    bin_path = logged_output(["swift", "build", "-c", configuration, "--show-bin-path", "--scratch-path", str(scratch)], package)
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
        command = [*time_arguments(time_path), str(executable), mode]
        try:
            completed = subprocess.run(command, check=True, capture_output=True, text=True)
        except subprocess.CalledProcessError as error:
            if ACTIVE_LOG:
                ACTIVE_LOG.save(command, Path.cwd(), error.stdout or "", error.stderr or "", error.returncode, time_path.read_text())
            raise
        if ACTIVE_LOG:
            ACTIVE_LOG.save(command, Path.cwd(), completed.stdout, completed.stderr, completed.returncode, time_path.read_text())
        return json.loads(completed.stdout), parse_rss(time_path)
    finally:
        time_path.unlink(missing_ok=True)


def validate_runner_results(first, sweep):
    if len(first) != RUNTIME_TRIALS or len(sweep) != RUNTIME_TRIALS:
        raise ValueError("runner trial count is invalid")
    for payload, rss in first:
        if type(rss) is not int or rss <= 0:
            raise ValueError("first-access RSS bytes are invalid")
        if payload.get("mode") != "first":
            raise ValueError("first-access runner mode is invalid")
        if payload.get("value") != EXPECTED_FIRST_VALUE:
            raise ValueError("first-access value does not match the generated model")
        if type(payload.get("elapsedNanoseconds")) is not int or payload["elapsedNanoseconds"] < 0:
            raise ValueError("first-access elapsed time is invalid")
    for payload, rss in sweep:
        if type(rss) is not int or rss <= 0:
            raise ValueError("full-sweep RSS bytes are invalid")
        if payload.get("mode") != "sweep":
            raise ValueError("full-sweep runner mode is invalid")
        if payload.get("checksum") != EXPECTED_WHOLE_MODEL_FNV64:
            raise ValueError("whole-model checksum does not match the generated model")
        if type(payload.get("elapsedNanoseconds")) is not int or payload["elapsedNanoseconds"] < 0:
            raise ValueError("full-sweep elapsed time is invalid")


def stripped_size(executable):
    with tempfile.TemporaryDirectory(prefix="model-prototype-strip-") as directory:
        copy = Path(directory) / executable.name
        shutil.copy2(executable, copy)
        logged_run(["strip", "-S" if platform.system() == "Darwin" else "--strip-debug", str(copy)], Path(directory))
        return copy.stat().st_size


def performance_module():
    path = ROOT / "Scripts/migration/performance_baseline.py"
    spec = importlib.util.spec_from_file_location("prototype_performance_baseline", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def environment():
    return performance_module().environment()


def load_baseline(path):
    baseline = json.loads(path.read_text())
    performance_module().check_record(baseline)
    return baseline


def compare_representation(baseline, measurements, measured_environment):
    if baseline["environment"] != measured_environment:
        raise ValueError("candidate environment differs from the supplied baseline")
    result = evaluate_builds(measurements, baseline["budgets"])
    result["summary"]["strippedExecutableBytes"] = measurements["strippedExecutableBytes"]
    if measurements["strippedExecutableBytes"] > baseline["budgets"]["strippedBinaryBytes"]:
        result["failures"].append("strippedExecutableBytes")
    result["passed"] = not result["failures"]
    return result


def packaging_manifest(package):
    if (package / "Scripts").exists() or (package / ".dev-tooling").exists():
        raise ValueError("consumer package contains development scripts or tooling")
    manifest = json.loads(logged_output(["swift", "package", "dump-package"], package))
    if manifest.get("dependencies"):
        raise ValueError("consumer package requires network dependencies")
    for target in manifest["targets"]:
        if target.get("resources") or target.get("pluginUsages"):
            raise ValueError("consumer package requires runtime data or build plugins")
    return manifest


CONSUMER_MANIFEST = """// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ModelConsumer", platforms: [.macOS(.v15)], dependencies: [.package(path: "../package")], targets: [.executableTarget(name: "ModelConsumer", dependencies: [.product(name: "AstronomyModelPrototype", package: "package")])])
"""
CONSUMER_SOURCE = """import AstronomyModelPrototype
let checksum = PrototypeModelData.wholeModelFNV64()
print(checksum)
"""


def verify_consumer(package, directory):
    manifest = packaging_manifest(package)
    consumer = directory / "consumer"
    (consumer / "Sources/ModelConsumer").mkdir(parents=True)
    (consumer / "Package.swift").write_text(CONSUMER_MANIFEST)
    (consumer / "Sources/ModelConsumer/main.swift").write_text(CONSUMER_SOURCE)
    logged_run(["swift", "build", "-c", "release", "--product", "ModelConsumer"], consumer)
    bin_path = logged_output(["swift", "build", "-c", "release", "--show-bin-path"], consumer)
    checksum = int(logged_output([str(Path(bin_path) / "ModelConsumer")], consumer))
    if checksum != EXPECTED_WHOLE_MODEL_FNV64:
        raise ValueError("clean consumer whole-model checksum mismatch")
    return {"scriptsCopied": False, "runtimeDataFiles": False, "networkDependencies": False, "buildPlugins": False,
            "completed": True, "wholeModelChecksum": checksum,
            "consumerManifestSHA256": hashlib.sha256(CONSUMER_MANIFEST.encode()).hexdigest(),
            "consumerSourceSHA256": hashlib.sha256(CONSUMER_SOURCE.encode()).hexdigest(),
            "evaluatedManifestSHA256": hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()}


def protocol():
    return {"schemaVersion": 2, "buildConfigurations": ["release", "debug"], "buildPreflightRunsPerConfiguration": 1,
            "buildTrialsPerConfiguration": BUILD_TRIALS, "incrementalTrialsPerConfiguration": BUILD_TRIALS,
            "runtimeTrialsPerMode": RUNTIME_TRIALS, "runtimeModes": ["first", "sweep"],
            "incrementalEdit": "ModelData.swift modification time only", "peakResidentUnit": "bytes",
            "buildCommand": ["swift", "build", "-c", "{configuration}", "--product", "AstronomyModelPrototypeRunner", "--scratch-path", "{scratch}"],
            "runtimeCommand": ["{runner}", "{mode}"], "timeFlagsBySystem": {"Darwin": "-l", "Linux": "-v"},
            "stripFlagsBySystem": {"Darwin": "-S", "Linux": "--strip-debug"}, "consumerBuildCommand": ["swift", "build", "-c", "release", "--product", "ModelConsumer"],
            "quantitativeGates": ["cleanReleaseSeconds", "incrementalReleaseSeconds", "strippedExecutableBytes"],
            "reservedPilotGates": ["astronomicalLatency", "astronomicalThroughput", "astronomicalRuntimeRSS"]}


def write_record(path, record):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(record, indent=2, sort_keys=True, allow_nan=False) + "\n")
    temporary.replace(path)


def validate_logs(receipt, output_path):
    if Path(receipt["directory"]).name != receipt["directory"]:
        raise ValueError("command log directory must be beside the output artifact")
    directory = output_path.parent / receipt["directory"]
    manifest = directory / "commands.json"
    if sha256(manifest) != receipt["manifestSHA256"]:
        raise ValueError("command log manifest hash differs")
    entries = json.loads(manifest.read_text())["entries"]
    if len(entries) != receipt["commandCount"] or not entries:
        raise ValueError("command log count differs")
    for entry in entries:
        if entry["returncode"] != 0:
            raise ValueError("command log contains a failed command")
        for item in entry["files"].values():
            if Path(item["path"]).name != item["path"] or sha256(directory / item["path"]) != item["sha256"]:
                raise ValueError("command log source hash differs")
    return directory, entries


def validate_logged_measurements(receipt, output_path, record):
    directory, entries = validate_logs(receipt, output_path)
    system = record["environment"]["system"]
    for configuration in ("release", "debug"):
        builds = [entry for entry in entries if entry["command"][:2] == ["/usr/bin/time", "-l" if system == "Darwin" else "-v"] and entry["command"][4:8] == ["swift", "build", "-c", configuration]]
        if len(builds) != 1 + 2 * BUILD_TRIALS:
            raise ValueError("logged build count differs from preflight and trials")
        for mode, group in (("clean", builds[1:4]), ("incremental", builds[4:7])):
            prefix = mode + configuration.title()
            if [entry.get("elapsedSeconds") for entry in group] != record["measurements"][prefix + "Seconds"]:
                raise ValueError("logged build timings differ")
            if [parse_rss(directory / entry["files"]["time"]["path"], system) for entry in group] != record["measurements"][prefix + "PeakResidentBytes"]:
                raise ValueError("logged compiler RSS differs")
    for mode, field, metric in (("first", "firstAccessResults", "firstAccessPeakResidentBytes"), ("sweep", "fullSweepResults", "fullSweepPeakResidentBytes")):
        probes = [entry for entry in entries if entry["command"][0] == "/usr/bin/time" and entry["command"][-1] == mode]
        if len(probes) != RUNTIME_TRIALS:
            raise ValueError("logged runtime probe count differs")
        if [json.loads((directory / entry["files"]["stdout"]["path"]).read_text()) for entry in probes] != record[field]:
            raise ValueError("logged runtime payload differs")
        if [parse_rss(directory / entry["files"]["time"]["path"], system) for entry in probes] != record["measurements"][metric]:
            raise ValueError("logged runtime RSS differs")
    consumers = [entry for entry in entries if entry["command"][:6] == ["swift", "build", "-c", "release", "--product", "ModelConsumer"]]
    if len(consumers) != 1:
        raise ValueError("logged clean consumer build is missing")


def record_digest(record):
    payload = {key: value for key, value in record.items() if key != "recordSHA256"}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def validate_record(record, baseline, baseline_path, output_path=None):
    if record.get("schemaVersion") != 2 or record.get("status") not in ("passed", "failed"):
        raise ValueError("representation evidence is incomplete")
    if record.get("recordSHA256") != record_digest(record):
        raise ValueError("representation record receipt hash differs")
    if record.get("protocol") != protocol():
        raise ValueError("representation protocol differs")
    inputs = record.get("inputSHA256")
    if inputs != prototype_inputs(ROOT):
        raise ValueError("prototype input hashes are stale")
    if record.get("baselineSHA256") != sha256(baseline_path):
        raise ValueError("supplied baseline hash differs")
    if record.get("historicalBaselineSHA256") != sha256(BASELINE):
        raise ValueError("historical baseline hash differs")
    if record.get("measurementProtocolSHA256") != inputs["Scripts/model-prototype/measure.py"] or record.get("workloadSHA256") != inputs["Tools/Migration/ModelPrototypeRunner/main.swift"]:
        raise ValueError("protocol or workload source binding differs")
    if record.get("fixedBudgets") != baseline["budgets"]:
        raise ValueError("fixed budgets differ from supplied baseline")
    for field in ("runnerSHA256",):
        if re.fullmatch(r"[0-9a-f]{64}", record.get(field, "")) is None:
            raise ValueError("runner artifact hash is invalid")
    if re.fullmatch(r"[0-9a-f]{40}", record.get("baseRevision", "")) is None:
        raise ValueError("base revision is invalid")
    if output_path is None:
        raise ValueError("output path is required to validate command logs")
    validate_logged_measurements(record["commandLogs"], output_path, record)
    validate_evidence(record["measurements"] | {"workloadSHA256": record["workloadSHA256"]})
    validate_runner_results([(payload, rss) for payload, rss in zip(record.get("firstAccessResults", []), record["measurements"]["firstAccessPeakResidentBytes"])],
                            [(payload, rss) for payload, rss in zip(record.get("fullSweepResults", []), record["measurements"]["fullSweepPeakResidentBytes"])])
    for field, metric in (("firstAccessResults", "firstAccessNanoseconds"), ("fullSweepResults", "fullSweepNanoseconds")):
        if [payload["elapsedNanoseconds"] for payload in record[field]] != record["measurements"][metric]:
            raise ValueError("runtime timing payload binding differs")
    packaging = record.get("consumerPackaging", {})
    if packaging.get("completed") is not True or packaging.get("wholeModelChecksum") != EXPECTED_WHOLE_MODEL_FNV64:
        raise ValueError("clean consumer packaging is incomplete")
    if any(packaging.get(key) is not False for key in ("scriptsCopied", "runtimeDataFiles", "networkDependencies", "buildPlugins")):
        raise ValueError("consumer packaging requires development or runtime assets")
    for key, contents in (("consumerManifestSHA256", CONSUMER_MANIFEST), ("consumerSourceSHA256", CONSUMER_SOURCE)):
        if packaging.get(key) != hashlib.sha256(contents.encode()).hexdigest():
            raise ValueError("consumer packaging source hash differs")
    if re.fullmatch(r"[0-9a-f]{64}", packaging.get("evaluatedManifestSHA256", "")) is None:
        raise ValueError("consumer evaluated manifest hash is invalid")
    result = compare_representation(baseline, record["measurements"], record["environment"])
    if record.get("evaluation") != result or record["status"] != ("passed" if result["passed"] else "failed"):
        raise ValueError("representation evaluation differs from measurements")
    return result


def measure(baseline_path, output_path):
    global ACTIVE_LOG
    if output_path.resolve() in (baseline_path.resolve(), OUTPUT.resolve(), BASELINE.resolve()):
        raise ValueError("output must not overwrite a baseline or historical evidence")
    for directory in ("Sources", "Tests", "Tools", "Scripts"):
        if output_path.resolve().is_relative_to((ROOT / directory).resolve()):
            raise ValueError("output artifacts must be outside source and script inputs")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    partial = {}
    phase = "initializing"

    def checkpoint(checkpoint_phase, values):
        nonlocal phase
        phase = checkpoint_phase
        partial.update(values)
        write_checkpoint(output_path, checkpoint_phase, partial)

    try:
        baseline = load_baseline(baseline_path)
        measured_environment = environment()
        if measured_environment != baseline["environment"]:
            raise ValueError("candidate environment differs from the supplied baseline")
        ACTIVE_LOG = CommandLog(output_path.with_suffix(output_path.suffix + ".logs"))
        base_revision = logged_output(["git", "rev-parse", "HEAD"], ROOT)
        before = prototype_inputs(ROOT)
        baseline_hash = sha256(baseline_path)
        historic_hash = sha256(BASELINE)
        write_checkpoint(output_path, phase, partial)
        with tempfile.TemporaryDirectory(prefix="astronomy-model-prototype-") as directory:
            package = Path(directory) / "package"
            phase = "workspace-copy"
            copy_workspace(package)
            for name, digest in before.items():
                if name == "Package.swift" or name.startswith(("Sources/", "Tests/", "Tools/")):
                    if sha256(package / name) != digest:
                        raise RuntimeError("copied prototype inputs differ: " + name)
            packaging_manifest(package)
            measurements = {}
            for configuration in ("release", "debug"):
                phase = configuration + "-build"
                builds, executable = build_trials(package, configuration, checkpoint)
                for name, values in builds.items():
                    mode = "incremental" if name.startswith("incremental") else "clean"
                    suffix = "PeakResidentBytes" if "Resident" in name else "Seconds"
                    measurements[f"{mode}{configuration.title()}{suffix}"] = values
                if configuration == "release":
                    release_executable = executable
            phase = "runtime-first"
            first = [timed_runner(release_executable, "first") for _ in range(RUNTIME_TRIALS)]
            phase = "runtime-sweep"
            sweep = [timed_runner(release_executable, "sweep") for _ in range(RUNTIME_TRIALS)]
            validate_runner_results(first, sweep)
            measurements.update({"firstAccessNanoseconds": [item[0]["elapsedNanoseconds"] for item in first],
                                 "firstAccessPeakResidentBytes": [item[1] for item in first],
                                 "fullSweepNanoseconds": [item[0]["elapsedNanoseconds"] for item in sweep],
                                 "fullSweepPeakResidentBytes": [item[1] for item in sweep]})
            phase = "strip"
            measurements["strippedExecutableBytes"] = stripped_size(release_executable)
            runner_hash = sha256(release_executable)
            phase = "consumer-packaging"
            packaging = verify_consumer(package, Path(directory))
        phase = "input-validation"
        require_unchanged_snapshot(before, prototype_inputs(ROOT))
        if baseline_hash != sha256(baseline_path) or historic_hash != sha256(BASELINE):
            raise RuntimeError("baseline changed during measurement")
        if measured_environment != environment():
            raise RuntimeError("environment changed during measurement")
        result = compare_representation(baseline, measurements, measured_environment)
        record = {"schemaVersion": 2, "status": "passed" if result["passed"] else "failed", "phase": "completed",
                  "scope": "Complete development-only Swift coefficient representation; astronomical runtime gates belong to issue #83",
                  "environment": measured_environment, "inputSHA256": before, "protocol": protocol(),
                  "baseRevision": base_revision, "ci": {key: os.environ[key] for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_SHA", "GITHUB_WORKFLOW", "RUNNER_OS", "RUNNER_ARCH") if key in os.environ},
                  "commandLogs": ACTIVE_LOG.receipt(),
                  "measurementProtocolSHA256": before["Scripts/model-prototype/measure.py"],
                  "baselineSHA256": baseline_hash, "historicalBaselineSHA256": historic_hash,
                  "workloadSHA256": before["Tools/Migration/ModelPrototypeRunner/main.swift"], "runnerSHA256": runner_hash,
                  "firstAccessResults": [item[0] for item in first], "fullSweepResults": [item[0] for item in sweep],
                  "measurements": measurements, "fixedBudgets": baseline["budgets"], "evaluation": result,
                  "consumerPackaging": packaging}
        record["recordSHA256"] = record_digest(record)
        phase = "evidence-validation"
        validate_record(record, baseline, baseline_path, output_path)
        phase = "final-write"
        write_record(output_path, record)
        return record
    except BaseException as error:
        try:
            write_checkpoint(output_path, phase, partial, str(error) or type(error).__name__)
        except BaseException:
            output_path.unlink(missing_ok=True)
        raise
    finally:
        ACTIVE_LOG = None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--measure", action="store_true")
    action.add_argument("--check", action="store_true")
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.measure:
        record = measure(args.baseline, args.output)
        result = record["evaluation"]
    else:
        result = validate_record(json.loads(args.output.read_text()), load_baseline(args.baseline), args.baseline, args.output)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
