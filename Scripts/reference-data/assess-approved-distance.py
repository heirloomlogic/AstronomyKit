#!/usr/bin/env python3
"""Retrospective comparison of archived distances with the approved product target."""

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "Documentation/Migration"
POLICY = DOCS / "approved-accuracy-targets.json"
OUTPUT = DOCS / "approved-distance-retrospective.json"
AU_KM = 149597870.7


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n"


def assess(reference_range_au, signed_error_km, relative_limit):
    if not all(math.isfinite(v) for v in (reference_range_au, signed_error_km, relative_limit)) or reference_range_au <= 0 or relative_limit <= 0:
        raise ValueError("invalid reference distance, residual or target")
    allowed_km = reference_range_au * AU_KM * relative_limit
    return {
        "allowedErrorKm": allowed_km,
        "absoluteErrorKm": abs(signed_error_km),
        "errorPPM": abs(signed_error_km) / (reference_range_au * AU_KM) * 1e6,
        "nominalTargetExceeded": abs(signed_error_km) > allowed_km,
    }


def relative_limit(policy, body):
    limits = policy["distance"]["maximumRelativeErrorByBody"]
    if body not in limits:
        raise ValueError(f"no approved distance limit for {body}")
    limit = limits[body]
    if not math.isfinite(limit) or limit <= 0:
        raise ValueError("invalid approved distance limit")
    return limit


def build_report():
    policy_bytes = POLICY.read_bytes()
    policy = json.loads(policy_bytes)
    if policy["distance"]["comparison"] != "lessThanOrEqual":
        raise ValueError("unexpected distance boundary")
    spec = importlib.util.spec_from_file_location("frozen_distance", ROOT / "Scripts/reference-data/distance-accuracy.py")
    archive = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(archive)
    if set(policy["distance"]["maximumRelativeErrorByBody"]) != set(archive.BODIES):
        raise ValueError("approved body-specific policy coverage mismatch")
    budget_bytes = archive.BUDGET.read_bytes()
    budget = json.loads(budget_bytes)
    characterization_bytes = archive.CHARACTERIZATION.read_bytes()
    if budget["characterizationSHA256"] != digest(characterization_bytes):
        raise ValueError("historical characterization detached from frozen budget")
    inputs = {p.relative_to(ROOT).as_posix(): digest(p.read_bytes()) for p in (POLICY, archive.BUDGET, archive.CHARACTERIZATION, archive.REPORT, Path(__file__))}
    phases = {}
    for phase, path, count in (("characterization", archive.CHARACTERIZATION, 131), ("prior-heldout", archive.REPORT, 134)):
        data = json.loads(path.read_bytes())
        archive_phase = "heldout" if phase == "prior-heldout" else phase
        if data["inputSHA256"] != archive.input_hashes(archive_phase):
            raise ValueError("historical source/query inputs changed")
        if phase == "prior-heldout" and data["allowancesSHA256"] != digest(budget_bytes):
            raise ValueError("historical heldout detached from frozen budget")
        summaries = {}
        seen = set()
        for row in data["results"]:
            key = f"{row['body'].lower()}-{row['mode']}"
            identity = (key, row["julianDateTT"])
            if identity in seen or not math.isfinite(row["julianDateTT"]) or not archive.START <= row["julianDateTT"] < archive.STOP:
                raise ValueError("duplicate or out-of-domain historical sample")
            seen.add(identity)
            limit = relative_limit(policy, row["body"])
            assessment = assess(row["referenceRangeAU"], row["signedRangeErrorKm"], limit)
            summary = summaries.setdefault(key, {"samples": 0, "nominalExceedances": 0, "maximumErrorPPM": -1, "targetPPM": limit * 1e6})
            summary["samples"] += 1
            summary["nominalExceedances"] += assessment["nominalTargetExceeded"]
            if assessment["errorPPM"] > summary["maximumErrorPPM"]:
                summary.update({"maximumErrorPPM": assessment["errorPPM"], "worstJulianDateTT": row["julianDateTT"], "worstAbsoluteErrorKm": assessment["absoluteErrorKm"], "allowedErrorKmAtWorstPPM": assessment["allowedErrorKm"], "alignmentRemainderEstimateKmAtWorstPPM": row["alignmentRemainderEstimateKm"]})
        wanted = {f"{body.lower()}-{mode}" for body, mode in archive.series()}
        if set(summaries) != wanted or any(row["samples"] != count for row in summaries.values()):
            raise ValueError("incomplete historical series coverage")
        phases[phase] = {"samples": len(seen), "nominalExceedances": sum(v["nominalExceedances"] for v in summaries.values()), "series": summaries}
    return {
        "schemaVersion": 1,
        "classification": "retrospective-product-target-assessment-not-new-holdout-or-qualification",
        "inputsSHA256": inputs,
        "requiredDomain": policy["domain"],
        "assessedDomain": "1900-01-01 <= TT < 2101-01-01",
        "maximumRelativeDistanceErrorByBody": policy["distance"]["maximumRelativeErrorByBody"],
        "nominalExceedanceCount": sum(v["nominalExceedances"] for v in phases.values()),
        "phases": phases,
        "limitations": [
            "These epochs and residuals were already observed before adopting the new target; the old heldout is not a fresh independent acceptance set for it.",
            "No new 2101-2130 samples are present; full required-domain qualification remains unperformed.",
            "Received-light references retain the historical fixed-Sun bridge and alignment estimates; no exact barycentric/public-default-aberration range equivalence is claimed.",
            "Nominal residual comparisons do not incorporate a certified physical-reference or convention-uncertainty bound. A non-exceedance is not a qualified pass.",
            "Moon results use its existing instantaneous geometric exception. Outer-planet/Pluto center semantics and vector-frame differences remain explicitly unresolved.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("report", "check"))
    args = parser.parse_args()
    result = encoded(build_report())
    if args.action == "check":
        if OUTPUT.read_text() != result:
            raise ValueError("stale retrospective assessment")
        print("retrospective assessment verified; no new accuracy qualification claimed")
    else:
        OUTPUT.write_text(result)
        print(f"wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
