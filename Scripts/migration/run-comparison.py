#!/usr/bin/env python3

import argparse
import copy
import gzip
import hashlib
import json
import math
import platform
import shutil
import struct
import subprocess
import tempfile
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CORPUS_PATH = ROOT / "Tools/Migration/Comparison/corpus.json"
POPULATION_LOCK_PATH = ROOT / "Tools/Migration/Comparison/downstream-populations-lock.json"
ARTIFACT_PATH = ROOT / "Tools/Migration/Comparison/Artifacts/reference"
ORACLE_LOCK_PATH = ROOT / "Tools/Migration/Oracle/oracle-lock.json"
ARCHIVE_FILES = (
    "inputs.json",
    "c-output.json",
    "swift-output.json",
    "diffs.json",
    "metadata.json",
    "downstream-populations.json",
)


def canonical_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def sha256_bytes(value):
    return hashlib.sha256(value).hexdigest()


def sha256_path(path):
    return sha256_bytes(path.read_bytes())


def macho_without_uuid(data):
    if len(data) < 32:
        return data
    magic = struct.unpack_from("<I", data)[0]
    if magic == 0xFEEDFACF:
        header_size = 32
    elif magic == 0xFEEDFACE:
        header_size = 28
    else:
        return data
    command_count = struct.unpack_from("<I", data, 16)[0]
    normalized = bytearray(data)
    offset = header_size
    for _ in range(command_count):
        if offset + 8 > len(normalized):
            raise ValueError("truncated Mach-O load command")
        command, size = struct.unpack_from("<II", normalized, offset)
        if size < 8 or offset + size > len(normalized):
            raise ValueError("invalid Mach-O load command size")
        if command == 0x1B:
            if size < 24:
                raise ValueError("invalid Mach-O UUID command")
            normalized[offset + 8 : offset + 24] = bytes(16)
        offset += size
    return bytes(normalized)


def executable_fingerprint(path):
    with tempfile.TemporaryDirectory(prefix="astronomykit-executable-fingerprint-") as directory:
        normalized = Path(directory) / path.name
        shutil.copy2(path, normalized)
        if platform.system() == "Darwin":
            subprocess.run(["codesign", "--remove-signature", str(normalized)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            strip_command = ["strip", "-S", str(normalized)]
        else:
            strip_command = ["strip", "--strip-debug", str(normalized)]
        subprocess.run(strip_command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return sha256_bytes(macho_without_uuid(normalized.read_bytes()))


def canonical_differences(expected, actual, path="$"):
    differences = []
    if type(expected) is not type(actual):
        return [{"path": path, "expected": expected, "actual": actual, "kind": "type"}]
    if isinstance(expected, dict):
        for key in sorted(set(expected) | set(actual)):
            child = f"{path}.{key}"
            if key not in expected:
                differences.append({"path": child, "expected": None, "actual": actual[key], "kind": "unexpected"})
            elif key not in actual:
                differences.append({"path": child, "expected": expected[key], "actual": None, "kind": "missing"})
            else:
                differences.extend(canonical_differences(expected[key], actual[key], child))
    elif isinstance(expected, list):
        for index in range(max(len(expected), len(actual))):
            child = f"{path}[{index}]"
            if index >= len(expected):
                differences.append({"path": child, "expected": None, "actual": actual[index], "kind": "unexpected"})
            elif index >= len(actual):
                differences.append({"path": child, "expected": expected[index], "actual": None, "kind": "missing"})
            else:
                differences.extend(canonical_differences(expected[index], actual[index], child))
    elif expected != actual:
        differences.append({"path": path, "expected": expected, "actual": actual, "kind": "value"})
    return differences


def comparison_passes(case, differences):
    accepted = case.get("acceptedDifference")
    if accepted is None:
        return not differences
    return differences == accepted["differences"]


def validate_corpus(corpus):
    required = {
        "positions",
        "derivatives",
        "events",
        "cold-warm",
        "delta-t-espenak-meeus",
        "delta-t-jpl-horizons",
        "stars",
        "pluto",
        "gravity",
        "chiron",
        "errors",
    }
    identifiers = [case["id"] for case in corpus["cases"]]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("corpus case identifiers must be unique")
    covered = {tag for case in corpus["cases"] for tag in case["coverage"]}
    missing = required - covered
    if missing:
        raise ValueError(f"corpus coverage is missing: {sorted(missing)}")
    for case in corpus["cases"]:
        if case["command"][-1] not in {"espenak-meeus", "jpl-horizons"}:
            raise ValueError(f"invalid Delta T model in {case['id']}")
        accepted = case.get("acceptedDifference")
        if accepted is not None:
            if case["id"] != "chiron-2020-em" or accepted.get("issue") != 108:
                raise ValueError(f"accepted difference is not authorized for {case['id']}")
            if set(accepted) != {"issue", "differences", "evidence", "reason"}:
                raise ValueError(f"invalid accepted difference in {case['id']}")
            differences = accepted["differences"]
            if not isinstance(differences, list) or not differences:
                raise ValueError(f"invalid accepted differences in {case['id']}")
            paths = []
            for difference in differences:
                if not isinstance(difference, dict) or set(difference) != {"path", "expected", "actual", "kind"}:
                    raise ValueError(f"invalid accepted difference record in {case['id']}")
                if difference["kind"] != "value" or not isinstance(difference["path"], str) or not difference["path"].startswith("$."):
                    raise ValueError(f"invalid accepted difference kind or path in {case['id']}")
                values = (difference["expected"], difference["actual"])
                if not all(isinstance(value, float) and math.isfinite(value) for value in values) or values[0] == values[1]:
                    raise ValueError(f"invalid accepted difference values in {case['id']}")
                paths.append(difference["path"])
            if len(paths) != len(set(paths)):
                raise ValueError(f"duplicate accepted difference path in {case['id']}")
            if not accepted["evidence"] or not all((ROOT / path).is_file() for path in accepted["evidence"]):
                raise ValueError(f"missing accepted difference evidence in {case['id']}")
            if not isinstance(accepted["reason"], str) or not accepted["reason"]:
                raise ValueError(f"missing accepted difference reason in {case['id']}")


def git_blob(revision, path):
    return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)


def recover_populations(lock):
    reports = []
    cases = []
    record = struct.Struct(lock["recordFormat"])
    if record.size != lock["recordSize"]:
        raise ValueError("population record size does not match its format")
    operation_names = {0: "position", 1: "state", 2: "distance"}
    for population in lock["populations"]:
        compressed = git_blob(lock["revision"], population["path"])
        if len(compressed) != population["compressedBytes"] or sha256_bytes(compressed) != population["sha256"]:
            raise ValueError(f"downstream population does not match lock: {population['name']}")
        payload = gzip.decompress(compressed)
        if len(payload) % record.size:
            raise ValueError(f"partial downstream record: {population['name']}")
        counts = Counter()
        selected = {}
        minimum_tt = None
        maximum_tt = None
        for thread, kind, body, active, tt in record.iter_unpack(payload):
            counts[(kind, body, active)] += 1
            minimum_tt = tt if minimum_tt is None else min(minimum_tt, tt)
            maximum_tt = tt if maximum_tt is None else max(maximum_tt, tt)
            if active == 1 and kind in operation_names and kind not in selected:
                selected[kind] = {"thread": thread, "kind": kind, "body": body, "active": active, "tt": tt}
        selections = []
        for kind in sorted(selected):
            item = selected[kind]
            identifier = f"downstream-{population['name']}-{operation_names[kind]}"
            command = [operation_names[kind], str(item["body"]), "tt", repr(item["tt"]), "1", "espenak-meeus"]
            cases.append({"id": identifier, "command": command, "coverage": ["downstream-population", population["name"]]})
            selections.append({**item, "caseId": identifier})
        reports.append(
            {
                "name": population["name"],
                "source": {"revision": lock["revision"], "path": population["path"], "sha256": population["sha256"]},
                "compressedBytes": len(compressed),
                "uncompressedBytes": len(payload),
                "recordCount": len(payload) // record.size,
                "ttRange": {"minimum": minimum_tt, "maximum": maximum_tt},
                "counts": [
                    {"kind": kind, "body": body, "active": active, "count": count}
                    for (kind, body, active), count in sorted(counts.items())
                ],
                "selectedRecords": selections,
            }
        )
    return {"schemaVersion": 1, "recordFormat": lock["recordFormat"], "populations": reports}, cases


def run_process(binary, command):
    completed = subprocess.run([str(binary), *command], cwd=ROOT, text=True, capture_output=True, check=False)
    stdout = completed.stdout.encode()
    parsed = None
    parse_error = None
    if completed.stdout:
        try:
            parsed = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            parse_error = str(error)
    return {
        "command": command,
        "process": {
            "exitCode": completed.returncode,
            "stdoutSha256": sha256_bytes(stdout),
            "stderr": completed.stderr,
            "parseError": parse_error,
        },
        "result": parsed,
    }


def compare_cases(cases, c_binary, swift_binary):
    c_outputs = []
    swift_outputs = []
    comparisons = []
    failed = []
    for case in cases:
        c_record = {"id": case["id"], **run_process(c_binary, case["command"])}
        swift_record = {"id": case["id"], **run_process(swift_binary, case["command"])}
        c_outputs.append(c_record)
        swift_outputs.append(swift_record)
        differences = canonical_differences(c_record["result"], swift_record["result"])
        if c_record["process"]["exitCode"] != swift_record["process"]["exitCode"]:
            differences.append(
                {
                    "path": "$.process.exitCode",
                    "expected": c_record["process"]["exitCode"],
                    "actual": swift_record["process"]["exitCode"],
                    "kind": "value",
                }
            )
        passed = comparison_passes(case, differences)
        comparison = {"id": case["id"], "differenceCount": len(differences), "differences": differences}
        if accepted := case.get("acceptedDifference"):
            comparison["acceptedDifference"] = accepted
            comparison["accepted"] = passed
        comparisons.append(comparison)
        if not passed:
            failed.append(case["id"])
    return c_outputs, swift_outputs, comparisons, failed


def negative_controls(c_outputs):
    successful = next(record["result"] for record in c_outputs if record["result"] and record["result"]["status"] == "success" and record["result"].get("samples"))
    numeric = copy.deepcopy(successful)
    numeric_value = numeric["samples"][0]["value"]
    numeric_key = next(key for key in sorted(numeric_value) if isinstance(numeric_value[key], float))
    numeric_value[numeric_key] += 1e-9

    status = copy.deepcopy(successful)
    status["status"] = "bad-time"
    model = copy.deepcopy(successful)
    model["model"] = "jpl-horizons" if successful["model"] == "espenak-meeus" else "espenak-meeus"
    event_source = next(record["result"] for record in c_outputs if record["result"] and len(record["result"].get("events", [])) >= 2)
    event_order = copy.deepcopy(event_source)
    event_order["events"][0], event_order["events"][1] = event_order["events"][1], event_order["events"][0]
    controls = {
        "numeric": canonical_differences(successful, numeric),
        "status": canonical_differences(successful, status),
        "timeModel": canonical_differences(successful, model),
        "eventOrder": canonical_differences(event_source, event_order),
    }
    if any(not differences for differences in controls.values()):
        raise ValueError("a negative control was not detected")
    return [{"name": name, "detected": differences} for name, differences in controls.items()]


def command_output(command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def manifest_for(files):
    return {"schemaVersion": 1, "files": {name: sha256_bytes(canonical_bytes(value)) for name, value in sorted(files.items())}}


def validate_archive(directory, manifest):
    if set(manifest["files"]) != set(ARCHIVE_FILES):
        raise ValueError("archive manifest has an incomplete file set")
    for name, digest in manifest["files"].items():
        path = directory / name
        if not path.is_file() or sha256_path(path) != digest:
            raise ValueError(f"archive digest mismatch: {name}")


def execution_module():
    import importlib.util
    spec = importlib.util.spec_from_file_location("comparison_execution", Path(__file__).with_name("comparison_execution.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def historical_replay(output=None):
    return execution_module().execute("historical", output)


def current_comparison(output=None):
    return execution_module().execute("current", output)


def main():
    parser = argparse.ArgumentParser(description="Execute isolated historical replay or a separately identified current comparison.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="Unsupported: original archive is immutable.")
    mode.add_argument("--check", action="store_true", help="Execute selected historical inputs; require original identity and closure for success.")
    mode.add_argument("--verify-evidence", type=Path, help="Validate saved raw/derived semantics and authenticated build receipts without new measurements.")
    mode.add_argument("--current", action="store_true", help="Execute current committed inputs under unchanged exact comparison obligations.")
    parser.add_argument("--output", type=Path, help="New evidence directory; an existing destination is rejected before acquisition.")
    arguments = parser.parse_args()
    if arguments.write:
        parser.error("the original archive cannot be rewritten; select --check or --current")
    if arguments.verify_evidence:
        report = execution_module().verify_evidence(arguments.verify_evidence)
        print(canonical_bytes(report).decode(), end="")
        return report
    report = historical_replay(arguments.output) if arguments.check else current_comparison(arguments.output)
    print(canonical_bytes(report).decode(), end="")
    passed = report.get("originalReproductionPassed") if arguments.check else report.get("scientificComparisonPassed")
    if passed is not True:
        raise SystemExit(1)
    return report


if __name__ == "__main__":
    main()
