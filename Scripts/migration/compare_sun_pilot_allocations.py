#!/usr/bin/env python3
"""Validate the finite paired Sun pilot decoded-allocation experiment."""
import argparse
import copy
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[2]
OPERATIONS = {"firstAccess": 1, "freshPolynomial": 200, "repeatedPolynomial": 200,
              "freshFallback": 200, "repeatedFallback": 200}
CHANGED_INPUTS = {"Sources/AstronomyModelPrototype/EarthPilot.swift",
                  "Sources/AstronomyModelPrototype/PilotOrientation.swift",
                  "Sources/AstronomyModelPrototype/ModelData.swift",
                  "Tests/AstronomySunPilotTests/SunPilotTests.swift",
                  ".github/workflows/sun-pilot.yml"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_reports(baseline, candidate):
    for record in (baseline, candidate):
        if (record["status"] != "complete-evidence" or record["diagnostic"]
                or record["candidateDirty"] or record["numericalPassed"] is not True):
            raise ValueError("requires clean, complete, nondiagnostic numerical campaigns")
    for key in ("environment", "protocolSHA256", "aggregateRSSProtocolSHA256"):
        if baseline[key] != candidate[key]:
            raise ValueError(f"changed comparison control: {key}")
    def package_control(record):
        package = copy.deepcopy(record["effectivePackage"])
        package.pop("evaluatedManifestSHA256", None)
        graph = package.get("evaluatedManifest")
        if graph is not None:
            graph["packageKind"] = {"root": ["<isolated-measurement-root>"]}
        return package
    if package_control(baseline) != package_control(candidate):
        raise ValueError("changed isolated package graph")
    # Binary hashes can differ with build-directory paths; frozen source/flags must match.
    baseline_oracle = {key: value for key, value in baseline["oracle"].items() if key != "binarySHA256"}
    candidate_oracle = {key: value for key, value in candidate["oracle"].items() if key != "binarySHA256"}
    if baseline_oracle != candidate_oracle:
        raise ValueError("changed frozen oracle")
    for key in ("baselineSHA256", "budgets"):
        if baseline["fixedBudgetObservations"][key] != candidate["fixedBudgetObservations"][key]:
            raise ValueError("changed frozen budget")
    ceiling = baseline["fixedBudgetObservations"]["budgets"]["peakResidentBytes"]
    if ceiling != 11182080:
        raise ValueError("unexpected original RSS ceiling")
    for path in set(baseline["sourceSHA256"]) | set(candidate["sourceSHA256"]):
        if path not in CHANGED_INPUTS and baseline["sourceSHA256"].get(path) != candidate["sourceSHA256"].get(path):
            raise ValueError(f"changed frozen source input: {path}")
    reference_workloads = None
    peaks = {}
    for label, record in (("baseline", baseline), ("candidate", candidate)):
        for configuration in ("debug", "release"):
            value = record["configurations"][configuration]
            comparison = value["comparison"]
            if (comparison["passed"] is not True or comparison["count"] != 67240
                    or comparison["failures"] or comparison["fallbackSamples"] <= 0
                    or value["perturbationDetected"] is not True or not value["perturbationFailures"]):
                raise ValueError("missing parity or fallback negative control")
            trials = value["runtime"]
            if len(trials) != 5:
                raise ValueError("requires five uninstrumented trials")
            peaks[f"{label}-{configuration}"] = []
            for trial in trials:
                rss = trial["peakResidentBytes"]
                if type(rss) is not int or rss <= 0:
                    raise ValueError("invalid RSS sample")
                peaks[f"{label}-{configuration}"].append(rss)
                workloads = trial["workloads"]
                if set(workloads) != set(OPERATIONS):
                    raise ValueError("changed workload modes")
                scalars = {}
                for mode, count in OPERATIONS.items():
                    item = workloads[mode]
                    if (type(item["operations"]) is not int or item["operations"] != count
                            or type(item["checksum"]) not in (int, float) or not math.isfinite(item["checksum"])):
                        raise ValueError("invalid workload count/checksum")
                    scalars[mode] = (count, item["checksum"])
                if reference_workloads is None:
                    reference_workloads = scalars
                if scalars != reference_workloads:
                    raise ValueError("changed workload checksums")
    old = peaks["baseline-release"]
    new = peaks["candidate-release"]
    separated = max(new) < min(old)
    return {"trialPeakResidentBytes": peaks, "releaseMedianReductionBytes": statistics.median(old) - statistics.median(new),
            "allCandidateReleaseTrialsBelowEveryBaselineTrial": separated,
            "rssRetentionConditionPassed": separated and baseline["environment"]["system"] == "Linux",
            "baselineWithinOriginalCeiling": max(old) <= ceiling,
            "candidateWithinOriginalCeiling": max(new) <= ceiling,
            "originalCeilingBytes": ceiling, "qualified": False}


def compare_directories(baseline, candidate):
    records = [json.loads((path / "report.json").read_text()) for path in (baseline, candidate)]
    result = validate_reports(*records)
    bound = {}
    for name in ("inputs.json.gz", "oracle.jsonl.gz", "debug.jsonl.gz", "release.jsonl.gz",
                 "debug-perturbed.jsonl.gz", "release-perturbed.jsonl.gz"):
        data = [gzip.decompress((path / name).read_bytes()) for path in (baseline, candidate)]
        if data[0] != data[1]:
            raise ValueError(f"baseline/candidate raw rows differ: {name}")
        bound[name] = hashlib.sha256(data[0]).hexdigest()
    result.update({"schemaVersion": 2, "status": "complete-paired-evidence", "matchingUncompressedSHA256": bound,
                   "protocolSHA256": digest(ROOT / "Documentation/Migration/SunPilotAllocationProtocol.md"),
                   "validatorSHA256": digest(Path(__file__)),
                   "reports": {label: {"revision": record["candidateRevision"], "reportSHA256": digest(path / "report.json")}
                               for label, record, path in zip(("baseline", "candidate"), records, (baseline, candidate))},
                   "environment": records[0]["environment"]})
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    result = compare_directories(arguments.baseline, arguments.candidate)
    with arguments.output.open("x") as stream:
        stream.write(json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n")
    print(json.dumps(result, sort_keys=True, allow_nan=False))


if __name__ == "__main__":
    main()
