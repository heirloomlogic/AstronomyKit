#!/usr/bin/env python3

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASELINE_MODULE_PATH = ROOT / "Scripts/migration/performance_baseline.py"
BASELINE_PATH = ROOT / "Documentation/Migration/performance-baseline.json"
CANDIDATE_PATH = ROOT / "Documentation/Migration/performance-candidate.json"


def load_baseline_module():
    spec = importlib.util.spec_from_file_location("performance_baseline", BASELINE_MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def artifact_provenance_sha256(artifact):
    payload = {
        "schemaVersion": artifact.get("schemaVersion"),
        "baselineProvenanceSHA256": artifact.get("baselineProvenanceSHA256"),
        "candidate": artifact.get("candidate"),
        "evaluation": artifact.get("evaluation"),
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return hashlib.sha256(encoded).hexdigest()


def make_artifact(baseline_module, baseline, candidate):
    baseline_module.validate_record(baseline)
    baseline_module.validate_record(candidate)
    evaluation = baseline_module.evaluate_candidate(baseline, candidate["measurements"])
    artifact = {
        "schemaVersion": 1,
        "baselineProvenanceSHA256": baseline["provenanceSHA256"],
        "candidate": candidate,
        "evaluation": evaluation,
    }
    artifact["provenanceSHA256"] = artifact_provenance_sha256(artifact)
    return artifact


def check_evidence(baseline_module, baseline, artifact, current_hashes):
    baseline_module.validate_record(baseline)
    if current_hashes == baseline["inputSHA256"]:
        return {"source": "frozen-baseline", "evaluation": baseline_module.evaluate_candidate(baseline, baseline["measurements"])}

    if artifact is None:
        raise ValueError("candidate evidence is required because the frozen input hashes differ")
    if artifact.get("provenanceSHA256") != artifact_provenance_sha256(artifact):
        raise ValueError("candidate artifact provenance checksum does not match")
    if artifact.get("schemaVersion") != 1:
        raise ValueError("unsupported candidate evidence schema")
    if artifact.get("baselineProvenanceSHA256") != baseline["provenanceSHA256"]:
        raise ValueError("candidate evidence refers to a different frozen baseline")

    candidate = baseline_module.validate_record(artifact.get("candidate", {}))
    if candidate["inputSHA256"] != current_hashes:
        raise ValueError("candidate input hashes are stale")
    if candidate["environment"] != baseline["environment"]:
        raise ValueError("candidate environment differs from the frozen baseline")
    baseline_module.validate_candidate_protocol(baseline, candidate)

    evaluation = baseline_module.evaluate_candidate(baseline, candidate["measurements"])
    if artifact.get("evaluation") != evaluation:
        raise ValueError("candidate evaluation does not match its measurements")
    if not evaluation["passed"]:
        raise ValueError(f"candidate fails frozen budgets: {evaluation['failures']}")
    return {"source": "measured-candidate", "evaluation": evaluation}


def read_json(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    arguments = parser.parse_args()

    baseline_module = load_baseline_module()
    baseline = read_json(BASELINE_PATH)
    if arguments.write:
        candidate = baseline_module.measure()
        artifact = make_artifact(baseline_module, baseline, candidate)
        if not artifact["evaluation"]["passed"]:
            raise SystemExit(f"candidate fails frozen budgets: {artifact['evaluation']['failures']}")
        CANDIDATE_PATH.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n")
        print(f"Wrote {CANDIDATE_PATH.relative_to(ROOT)}")
        return

    artifact = read_json(CANDIDATE_PATH) if CANDIDATE_PATH.exists() else None
    result = check_evidence(baseline_module, baseline, artifact, baseline_module.source_hashes())
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, IndexError) as error:
        print(f"error: {error}")
        raise SystemExit(1)
