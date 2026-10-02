#!/usr/bin/env python3

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
PROTOCOL_PATH = Path(__file__).with_name("performance_baseline.py")
PROTOCOL_SPEC = importlib.util.spec_from_file_location("performance_baseline", PROTOCOL_PATH)
protocol = importlib.util.module_from_spec(PROTOCOL_SPEC)
PROTOCOL_SPEC.loader.exec_module(protocol)


FROZEN_INPUT_REVISION = "fad9e9b5d8e3dd823d1ce1f25c51b80ac23b11ff"


def revision_input_paths(revision):
    command = ["git", "ls-tree", "-r", "--name-only", revision, "--", "Sources/AstronomyKit", "Sources/CLibAstronomy"]
    output = subprocess.check_output(command, cwd=ROOT, text=True)
    dynamic = {
        path
        for path in output.splitlines()
        if path.startswith("Sources/CLibAstronomy/") or (path.startswith("Sources/AstronomyKit/") and path.endswith(".swift"))
    }
    return sorted(set(protocol.INPUT_PATHS) | dynamic)


def revision_source_hashes(revision=FROZEN_INPUT_REVISION):
    hashes = {}
    for path in revision_input_paths(revision):
        content = subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)
        hashes[path] = hashlib.sha256(content).hexdigest()
    return hashes


def verify_record(record, frozen_hashes):
    protocol.validate_record(record)
    recorded_hashes = record["inputSHA256"]
    missing = sorted(set(frozen_hashes) - set(recorded_hashes))
    extra = sorted(set(recorded_hashes) - set(frozen_hashes))
    if missing or extra:
        raise ValueError(f"performance baseline input paths differ from the frozen snapshot: missing={missing}, extra={extra}")
    mismatches = sorted(path for path in frozen_hashes if recorded_hashes[path] != frozen_hashes[path])
    if mismatches:
        raise ValueError(f"performance baseline input hashes differ from the frozen snapshot: {mismatches}")
    result = protocol.evaluate_candidate(record, record["measurements"])
    if not result["passed"]:
        raise ValueError(f"recorded baseline fails its own budgets: {result['failures']}")
    return result


def main():
    record = json.loads(protocol.BASELINE_PATH.read_text())
    result = verify_record(record, revision_source_hashes())
    print(json.dumps({"evaluation": result, "frozenInputRevision": FROZEN_INPUT_REVISION, "inputCount": len(record["inputSHA256"])}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
