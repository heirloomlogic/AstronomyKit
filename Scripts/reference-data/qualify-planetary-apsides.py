#!/usr/bin/env python3
"""Finite geometric Sun-center planetary apsis reference evidence."""
import argparse
import hashlib
import importlib.util
import json
import math
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "Documentation/Migration"
PLAN = DOCS / "planetary-apsis-sampling-plan.json"
POLICY = DOCS / "approved-accuracy-targets.json"
REPORT = DOCS / "planetary-apsis-assessment.json"
RAW = ROOT / "Scripts/reference-data/sources/planetary-apsides"
BINARY = ROOT / ".context/accuracy-qualification/build-runner/debug/AccuracyQualificationRunner"
POSITION_SPEC = importlib.util.spec_from_file_location("position_events", Path(__file__).with_name("qualify-position-events.py"))
Q = importlib.util.module_from_spec(POSITION_SPEC)
POSITION_SPEC.loader.exec_module(Q)


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def load_plan():
    plan = json.loads(PLAN.read_bytes())
    if plan["policySHA256"] != digest(POLICY.read_bytes()):
        raise ValueError("planetary apsis plan detached from approved policy")
    expected = ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune", "Pluto"]
    if list(plan["bodies"]) != expected:
        raise ValueError("planetary apsis plan must contain the nine ordered bodies")
    if plan["domain"]["startInclusiveJulianDateTT"] != 2415020.5 or plan["domain"]["stopExclusiveJulianDateTT"] != 2499391.5:
        raise ValueError("planetary apsis plan domain changed")
    if plan["rootResolution"]["referenceNumericalAllowanceSeconds"] != 1.0:
        raise ValueError("planetary apsis numerical allowance changed")
    if plan["publicPairing"]["timingTargetSeconds"] != 60.0 or plan["publicPairing"]["timingComparison"] != "strictlyLessThan":
        raise ValueError("planetary apsis timing target changed")
    return plan


def reference_recipe(body, dates):
    recipe = Q.parameters(body["targetID"], "10", "NONE", dates)
    validate_reference_recipe(recipe, body)
    return recipe


def validate_reference_recipe(recipe, body):
    expected = {
        "COMMAND": f"'{body['targetID']}'",
        "OBJ_DATA": "'NO'",
        "MAKE_EPHEM": "'YES'",
        "EPHEM_TYPE": "'VECTORS'",
        "CENTER": "'500@10'",
        "TLIST_TYPE": "'JD'",
        "TIME_TYPE": "'TT'",
        "REF_SYSTEM": "'ICRF'",
        "REF_PLANE": "'FRAME'",
        "OUT_UNITS": "'AU-D'",
        "VEC_TABLE": "'3'",
        "VEC_CORR": "'NONE'",
        "CSV_FORMAT": "'YES'",
        "CAL_TYPE": "'GREGORIAN'",
    }
    if any(recipe.get(key) != value for key, value in expected.items()):
        raise ValueError("reference recipe conventions changed")
    dates = recipe.get("TLIST", "''").strip("'").split(",")
    if not dates or len(dates) > 10_000:
        raise ValueError("reference recipe has invalid date population")


def coarse_dates(plan, body):
    start = plan["domain"]["startInclusiveJulianDateTT"]
    stop = plan["domain"]["stopExclusiveJulianDateTT"]
    step = body["coarseStepDays"]
    dates = [start - step]
    cursor = start
    while cursor < stop:
        dates.append(round(cursor, 8))
        cursor += step
    if dates[-1] != stop:
        dates.append(stop)
    if len(dates) > 10_000 or any(a >= b for a, b in zip(dates, dates[1:])):
        raise ValueError("invalid coarse reference schedule")
    return dates


def archive_pair(name, recipe, acquire=False):
    response_path = RAW / f"{name}.json"
    query_path = RAW / f"{name}.query.json"
    validate_reference_recipe(recipe, next(body for body in load_plan()["bodies"].values() if f"'{body['targetID']}'" == recipe["COMMAND"]))
    if response_path.exists() != query_path.exists():
        raise ValueError("incomplete planetary apsis response/query pair")
    if acquire and not response_path.exists():
        data = Q.download(recipe)
        RAW.mkdir(parents=True, exist_ok=True)
        response_path.write_bytes(data)
        query_path.write_bytes(encoded({"parameters": recipe, "responseSHA256": digest(data), "planSHA256": digest(PLAN.read_bytes())}))
    saved = json.loads(query_path.read_bytes())
    data = response_path.read_bytes()
    if saved != {"parameters": recipe, "responseSHA256": digest(data), "planSHA256": digest(PLAN.read_bytes())}:
        raise ValueError("detached planetary apsis response, query, or plan")
    return Q.parse_response(data, recipe)


def interpolate(rows, jd, field, degree=3):
    intervals = Q.brackets(rows)
    if len(intervals) != 1:
        raise ValueError("expected one range-rate crossing for interpolation")
    i, _ = intervals[0]
    offset = max(0, min(i - 1, len(rows) - degree - 1))
    selected = rows[offset : offset + degree + 1]
    projected = [{"julianDateTT": row["julianDateTT"], "rangeRateAUPerDay": row[field]} for row in selected]
    return Q.polynomial(projected, jd)


def stage_root(samples):
    retained = [dict(row) for row in samples]
    try:
        if len(samples) != 5:
            raise ValueError("root stage requires five samples")
        if any(
            not all(math.isfinite(row.get(key, math.nan)) for key in ("julianDateTT", "rangeRateAUPerDay", "rangeAU")) or row["rangeAU"] <= 0
            for row in samples
        ):
            raise ValueError("root stage has invalid reference samples")
        if any(a["julianDateTT"] >= b["julianDateTT"] for a, b in zip(samples, samples[1:])):
            raise ValueError("root stage epochs are not strictly ordered")
        if len(Q.brackets(samples)) != 1:
            raise ValueError("root stage does not contain one directed crossing")
        cubic, kind = Q.interpolated_root(samples, 3)
        quadratic, quadratic_kind = Q.interpolated_root(samples, 2)
        if kind != quadratic_kind:
            raise ValueError("root kind changes between interpolants")
        distance = interpolate(samples, cubic, "rangeAU", 3)
        if not math.isfinite(distance) or distance <= 0:
            raise ValueError("interpolated root distance is invalid")
        return {
            "status": "resolved",
            "julianDateTT": cubic,
            "kind": kind,
            "rangeAU": distance,
            "quadraticJulianDateTT": quadratic,
            "quadraticDifferenceSeconds": abs(cubic - quadratic) * 86_400,
            "samples": retained,
        }
    except (KeyError, TypeError, ValueError) as error:
        return {"status": "inconclusive", "reason": str(error), "samples": retained}


def finalize_root(coarse, medium, fine, numerical_allowance_seconds):
    stages = {"coarse": coarse, "medium": medium, "fine": fine}
    if any(stage.get("status") != "resolved" for stage in stages.values()):
        return {"status": "inconclusive", "reason": "one or more root stages were inconclusive", "stages": stages}
    if len({stage["kind"] for stage in stages.values()}) != 1:
        return {"status": "inconclusive", "reason": "root kind changed across refinement stages", "stages": stages}
    if fine["quadraticDifferenceSeconds"] > numerical_allowance_seconds:
        return {"status": "inconclusive", "reason": "fine root exceeds frozen cubic-quadratic allowance", "stages": stages}
    return {
        "status": "resolved",
        "julianDateTT": fine["julianDateTT"],
        "kind": fine["kind"],
        "rangeAU": fine["rangeAU"],
        "quadraticDifferenceSeconds": fine["quadraticDifferenceSeconds"],
        "coarseToMediumDifferenceSeconds": abs(coarse["julianDateTT"] - medium["julianDateTT"]) * 86_400,
        "mediumToFineDifferenceSeconds": abs(medium["julianDateTT"] - fine["julianDateTT"]) * 86_400,
        "stages": stages,
    }


def root_receipt(root):
    def stage_receipt(stage):
        return {
            **{key: value for key, value in stage.items() if key != "samples"},
            "sampleJulianDatesTT": [sample["julianDateTT"] for sample in stage.get("samples", [])],
        }

    return {
        **{key: value for key, value in root.items() if key != "stages"},
        "stages": {name: stage_receipt(stage) for name, stage in root.get("stages", {}).items()},
    }


def coarse_candidates(rows, start, stop):
    candidates = []
    for i, _ in Q.brackets(rows):
        offset = max(0, min(i - 2, len(rows) - 5))
        candidate = stage_root(rows[offset : offset + 5])
        if candidate.get("status") == "resolved" and not start <= candidate["julianDateTT"] < stop:
            continue
        candidates.append(candidate)
    return candidates


def stage_dates(candidates, offsets_seconds):
    dates = sorted(
        {
            round(candidate["julianDateTT"] + offset / 86_400, 8)
            for candidate in candidates
            if candidate.get("status") == "resolved"
            for offset in offsets_seconds
        }
    )
    if len(dates) > 10_000:
        raise ValueError("root refinement exceeds Horizons TLIST limit")
    return dates


def refine_candidates(candidates, rows, offsets_seconds):
    by_date = {round(row["julianDateTT"], 8): row for row in rows}
    refined = []
    for candidate in candidates:
        if candidate.get("status") != "resolved":
            refined.append({"status": "inconclusive", "reason": "prior root stage was inconclusive", "samples": []})
            continue
        try:
            samples = [by_date[round(candidate["julianDateTT"] + offset / 86_400, 8)] for offset in offsets_seconds]
        except KeyError:
            refined.append({"status": "inconclusive", "reason": "missing root refinement sample", "samples": []})
            continue
        refined.append(stage_root(samples))
    return refined


def acquire_refinement_stage(body_name, stage_name, body, candidates, offsets, acquire):
    dates = stage_dates(candidates, offsets)
    if not dates:
        return refine_candidates(candidates, [], offsets), {
            "status": "not-queried",
            "reason": "no resolved prior-stage roots supplied refinement dates",
            "planSHA256": digest(PLAN.read_bytes()),
        }
    rows, metadata = archive_pair(f"{body_name.lower()}-{stage_name}", reference_recipe(body, dates), acquire)
    return refine_candidates(candidates, rows, offsets), metadata


def references(body_name, body, acquire=False):
    plan = load_plan()
    start = plan["domain"]["startInclusiveJulianDateTT"]
    stop = plan["domain"]["stopExclusiveJulianDateTT"]
    coarse_rows, coarse_meta = archive_pair(body_name.lower() + "-coarse", reference_recipe(body, coarse_dates(plan, body)), acquire)
    coarse = coarse_candidates(coarse_rows, start, stop)
    medium_offsets = plan["rootResolution"]["mediumOffsetsSeconds"]
    medium, medium_meta = acquire_refinement_stage(body_name, "medium", body, coarse, medium_offsets, acquire)
    fine_offsets = plan["rootResolution"]["fineOffsetsSeconds"]
    fine, fine_meta = acquire_refinement_stage(body_name, "fine", body, medium, fine_offsets, acquire)
    allowance = plan["rootResolution"]["referenceNumericalAllowanceSeconds"]
    roots = [finalize_root(a, b, c, allowance) for a, b, c in zip(coarse, medium, fine)]
    return roots, {"coarse": coarse_meta, "medium": medium_meta, "fine": fine_meta}


def classify_orbit_scale_roots(roots, period_days, start, stop):
    threshold = period_days / 8
    ordered = sorted((dict(root) for root in roots if root.get("status") == "resolved"), key=lambda row: row["julianDateTT"])
    groups = []
    for root in ordered:
        if not groups or root["julianDateTT"] - groups[-1][-1]["julianDateTT"] >= threshold:
            groups.append([root])
        else:
            groups[-1].append(root)
    candidates = []
    additional = []
    ambiguous = []
    for group in groups:
        boundary_clipped = group[0]["julianDateTT"] - start < threshold or stop - group[-1]["julianDateTT"] < threshold
        alternating = all(a["kind"] != b["kind"] for a, b in zip(group, group[1:]))
        if boundary_clipped:
            ambiguous.append({"reason": "boundary-clipped root cluster", "roots": group})
        elif len(group) == 1:
            candidates.append({**group[0], "identityClassification": "singleton-orbit-scale-candidate"})
        elif len(group) % 2 == 1 and alternating and group[0]["kind"] == group[-1]["kind"]:
            repeated_kind = group[0]["kind"]
            choices = [root for root in group if root["kind"] == repeated_kind]
            selected = min(choices, key=lambda row: row["rangeAU"]) if repeated_kind == "pericenter" else max(choices, key=lambda row: row["rangeAU"])
            candidates.append({**selected, "identityClassification": "cluster-extreme-orbit-scale-candidate", "clusterSize": len(group)})
            additional.extend({**root, "identityClassification": "additional-local-extremum"} for root in group if root is not selected)
        else:
            ambiguous.append({"reason": "cluster does not satisfy frozen odd alternating rule", "roots": group})
    return {"orbitScaleCandidates": candidates, "additionalLocalExtrema": additional, "ambiguousClusters": ambiguous}


def nominal_within_timing_target(error_seconds, limit_seconds):
    return abs(error_seconds) < limit_seconds


def pair_public_events(public, references, period_days, numerical_allowance_seconds, distance_limit):
    threshold = period_days / 8
    public_order_valid = all(a["julianDateTT"] < b["julianDateTT"] for a, b in zip(public, public[1:]))
    public_alternation_valid = all(a["kind"] != b["kind"] for a, b in zip(public, public[1:]))
    count_matches = len(public) == len(references)
    kind_sequence_matches = [row["kind"] for row in public] == [row["kind"] for row in references]
    used = set()
    pairs = []
    failures = []
    previous_reference_jd = -math.inf
    for public_index, event in enumerate(public):
        candidates = [
            (index, reference)
            for index, reference in enumerate(references)
            if index not in used and event["kind"] == reference["kind"] and abs(event["julianDateTT"] - reference["julianDateTT"]) <= threshold
        ]
        if len(candidates) != 1:
            failures.append({"type": "unmatched-public" if not candidates else "ambiguous-public", "publicIndex": public_index, "public": event, "candidateReferenceIndices": [index for index, _ in candidates]})
            continue
        reference_index, reference = candidates[0]
        if reference["julianDateTT"] <= previous_reference_jd:
            failures.append({"type": "reference-order", "publicIndex": public_index, "referenceIndex": reference_index})
            continue
        used.add(reference_index)
        previous_reference_jd = reference["julianDateTT"]
        error_seconds = (event["julianDateTT"] - reference["julianDateTT"]) * 86_400
        relative_distance_error = (event["distanceAU"] - reference["rangeAU"]) / reference["rangeAU"]
        pairs.append(
            {
                "publicIndex": public_index,
                "referenceIndex": reference_index,
                "public": event,
                "reference": reference,
                "signedTimeErrorSeconds": error_seconds,
                "nominalWithinTimingTarget": nominal_within_timing_target(error_seconds, 60.0),
                "timingNumericalEnvelopeClassification": Q.event_classification(error_seconds, numerical_allowance_seconds),
                "signedDistanceErrorPPM": relative_distance_error * 1_000_000,
                "nominalWithinDistanceTarget": abs(relative_distance_error) <= distance_limit,
            }
        )
    unpaired = [{"referenceIndex": index, "reference": reference} for index, reference in enumerate(references) if index not in used]
    failures.extend({"type": "unpaired-reference", **row} for row in unpaired)
    return {
        "countMatches": count_matches,
        "kindSequenceMatches": kind_sequence_matches,
        "publicOrderValid": public_order_valid,
        "publicAlternationValid": public_alternation_valid,
        "pairs": pairs,
        "pairingFailures": failures,
        "unpairedReferences": unpaired,
    }


def public_batch(requests, binary):
    output = subprocess.check_output([str(binary), "accuracy-batch"], input="".join(json.dumps(request) + "\n" for request in requests), text=True)
    actuals = [json.loads(line) for line in output.splitlines()]
    if len(actuals) != len(requests):
        raise ValueError("public apsis response count differs from requests")
    for request, actual in zip(requests, actuals):
        if actual.get("status") != "success" or actual.get("request") != request:
            raise ValueError("public apsis status or request identity mismatch")
        previous = None
        for event in actual.get("events", []):
            if event.get("kind") not in ("pericenter", "apocenter") or not all(math.isfinite(event.get(key, math.nan)) for key in ("julianDateTT", "distanceAU")) or event["distanceAU"] <= 0:
                raise ValueError("invalid public planetary apsis event")
            if not request["startJulianDateTT"] <= event["julianDateTT"] < request["stopJulianDateTT"]:
                raise ValueError("public planetary apsis outside request")
            if previous and (event["julianDateTT"] <= previous["julianDateTT"] or event["kind"] == previous["kind"]):
                raise ValueError("public planetary apsides are not ordered and alternating")
            previous = event
    return actuals


def diagnostic_slices(plan, roots, classification, public):
    result = {}
    for slice_plan in plan["diagnosticSlices"]:
        start = slice_plan["startInclusiveJulianDateTT"]
        stop = slice_plan["stopExclusiveJulianDateTT"]
        inside = lambda row: start <= row["julianDateTT"] < stop
        result[slice_plan["id"]] = {
            "resolvedRawRoots": sum(root.get("status") == "resolved" and inside(root) for root in roots),
            "inconclusiveRoots": sum(root.get("status") != "resolved" and any(start <= sample["julianDateTT"] < stop for stage in root.get("stages", {}).values() for sample in stage.get("samples", [])) for root in roots),
            "orbitScaleCandidates": sum(inside(root) for root in classification["orbitScaleCandidates"]),
            "additionalLocalExtrema": sum(inside(root) for root in classification["additionalLocalExtrema"]),
            "publicEvents": sum(inside(event) for event in public),
        }
    return result


def normalized_body_evidence(roots, identity, public, pairing):
    raw_index = {(root["kind"], root["julianDateTT"]): index for index, root in enumerate(roots) if root.get("status") == "resolved"}
    candidate_raw_indices = [raw_index[(root["kind"], root["julianDateTT"])] for root in identity["orbitScaleCandidates"]]
    candidate_receipts = [
        {
            "rawRootIndex": raw_root_index,
            "identityClassification": root["identityClassification"],
            **({"clusterSize": root["clusterSize"]} if "clusterSize" in root else {}),
        }
        for raw_root_index, root in zip(candidate_raw_indices, identity["orbitScaleCandidates"])
    ]
    additional_receipts = [
        {"rawRootIndex": raw_index[(root["kind"], root["julianDateTT"])], "identityClassification": root["identityClassification"]}
        for root in identity["additionalLocalExtrema"]
    ]
    ambiguous_receipts = [
        {"reason": cluster["reason"], "rawRootIndices": [raw_index[(root["kind"], root["julianDateTT"])] for root in cluster["roots"]]}
        for cluster in identity["ambiguousClusters"]
    ]
    pair_receipts = []
    for pair in pairing["pairs"]:
        pair_receipts.append(
            {
                **{key: value for key, value in pair.items() if key not in ("public", "reference", "referenceIndex")},
                "orbitScaleCandidateIndex": pair["referenceIndex"],
                "rawRootIndex": candidate_raw_indices[pair["referenceIndex"]],
            }
        )
    failure_receipts = [{key: value for key, value in failure.items() if key not in ("public", "reference")} for failure in pairing["pairingFailures"]]
    comparison = {key: value for key, value in pairing.items() if key not in ("pairs", "pairingFailures", "unpairedReferences")}
    comparison.update({"pairs": pair_receipts, "pairingFailures": failure_receipts})
    return {
        "rawRoots": [root_receipt(root) for root in roots],
        "orbitScaleCandidates": candidate_receipts,
        "additionalLocalExtrema": additional_receipts,
        "ambiguousClusters": ambiguous_receipts,
        "publicEvents": public,
        "comparison": comparison,
    }


def input_hashes():
    paths = [PLAN, POLICY, Path(__file__), Path(__file__).with_name("test_planetary_apsides.py"), ROOT / "Scripts/reference-data/build-accuracy-runner.py", ROOT / "Package.swift"]
    for directory, patterns in [(RAW, ["*.json"]), (ROOT / "Sources/CLibAstronomy", ["*.c", "*.h"]), (ROOT / "Sources/AstronomyKit", ["*.swift"]), (ROOT / "Tools/Migration/AccuracyQualificationRunner", ["*.swift"])]:
        for pattern in patterns:
            paths += sorted(directory.rglob(pattern))
    return {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in sorted(set(paths))}


def acquire():
    for body_name, body in load_plan()["bodies"].items():
        roots, _ = references(body_name, body, True)
        print(f"archived {body_name}: {len(roots)} raw roots", flush=True)


def assess(binary):
    plan = load_plan()
    policy = json.loads(POLICY.read_bytes())
    start = plan["domain"]["startInclusiveJulianDateTT"]
    stop = plan["domain"]["stopExclusiveJulianDateTT"]
    reference_data = {}
    requests = []
    for body_name, body in plan["bodies"].items():
        roots, provenance = references(body_name, body)
        reference_data[body_name] = {"roots": roots, "provenance": provenance}
        requests.append({"operation": "planetary-apsides", "body": body["publicCode"], "startJulianDateTT": start, "stopJulianDateTT": stop})
    actuals = public_batch(requests, binary)
    bodies = {}
    for (body_name, body), actual in zip(plan["bodies"].items(), actuals):
        roots = reference_data[body_name]["roots"]
        resolved = [root for root in roots if root.get("status") == "resolved"]
        identity = classify_orbit_scale_roots(resolved, body["meanOrbitDays"], start, stop)
        pairing = pair_public_events(actual["events"], identity["orbitScaleCandidates"], body["meanOrbitDays"], plan["rootResolution"]["referenceNumericalAllowanceSeconds"], policy["distance"]["maximumRelativeErrorByBody"][body_name])
        pairs = pairing["pairs"]
        normalized = normalized_body_evidence(roots, identity, actual["events"], pairing)
        bodies[body_name] = {
            "source": reference_data[body_name]["provenance"],
            **normalized,
            "diagnosticSlices": diagnostic_slices(plan, roots, identity, actual["events"]),
            "summary": {
                "rawRootCount": len(roots),
                "resolvedRawRootCount": len(resolved),
                "inconclusiveRootCount": len(roots) - len(resolved),
                "orbitScaleCandidateCount": len(identity["orbitScaleCandidates"]),
                "additionalLocalExtremumCount": len(identity["additionalLocalExtrema"]),
                "ambiguousClusterCount": len(identity["ambiguousClusters"]),
                "publicEventCount": len(actual["events"]),
                "pairedEventCount": len(pairs),
                "pairingFailureCount": len(pairing["pairingFailures"]),
                "countMatches": pairing["countMatches"],
                "kindSequenceMatches": pairing["kindSequenceMatches"],
                "publicOrderValid": pairing["publicOrderValid"],
                "publicAlternationValid": pairing["publicAlternationValid"],
                "nominalTimingExceedanceCount": sum(not pair["nominalWithinTimingTarget"] for pair in pairs),
                "numericalEnvelopeExceedanceCount": sum(pair["timingNumericalEnvelopeClassification"] == "exceeded" for pair in pairs),
                "inconclusiveTimingEnvelopeCount": sum(pair["timingNumericalEnvelopeClassification"] == "inconclusive-numerical-envelope" for pair in pairs),
                "distanceExceedanceCount": sum(not pair["nominalWithinDistanceTarget"] for pair in pairs),
                "maximumAbsoluteTimeErrorSeconds": max((abs(pair["signedTimeErrorSeconds"]) for pair in pairs), default=None),
                "maximumAbsoluteDistanceErrorPPM": max((abs(pair["signedDistanceErrorPPM"]) for pair in pairs), default=None),
            },
        }
    summaries = {name: result["summary"] for name, result in bodies.items()}
    return {
        "schemaVersion": 1,
        "classification": "finite-geometric-planetary-apsis-public-api-evidence-not-continuous-or-physical-uncertainty-qualification",
        "qualified": False,
        "candidateRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "candidateDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
        "planSHA256": digest(PLAN.read_bytes()),
        "inputSHA256": input_hashes(),
        "referenceConventions": plan["referenceSource"],
        "executableProvenance": {
            "path": str(binary.resolve().relative_to(ROOT)) if binary.resolve().is_relative_to(ROOT) else str(binary.resolve()),
            "sha256": digest(binary.read_bytes()),
            "swiftVersion": subprocess.check_output(["swift", "--version"], text=True).strip(),
            "platform": platform.platform(),
            "buildManifestSHA256": digest((ROOT / ".context/accuracy-qualification/runner-package/Package.swift").read_bytes()),
            "expectedBuildCommand": "python3 Scripts/reference-data/build-accuracy-runner.py",
        },
        "summaries": summaries,
        "bodies": bodies,
        "totals": {
            "bodies": len(bodies),
            "rawRoots": sum(row["rawRootCount"] for row in summaries.values()),
            "inconclusiveRoots": sum(row["inconclusiveRootCount"] for row in summaries.values()),
            "orbitScaleCandidates": sum(row["orbitScaleCandidateCount"] for row in summaries.values()),
            "additionalLocalExtrema": sum(row["additionalLocalExtremumCount"] for row in summaries.values()),
            "ambiguousClusters": sum(row["ambiguousClusterCount"] for row in summaries.values()),
            "publicEvents": sum(row["publicEventCount"] for row in summaries.values()),
            "pairedEvents": sum(row["pairedEventCount"] for row in summaries.values()),
            "pairingFailures": sum(row["pairingFailureCount"] for row in summaries.values()),
            "nominalTimingExceedances": sum(row["nominalTimingExceedanceCount"] for row in summaries.values()),
            "numericalEnvelopeExceedances": sum(row["numericalEnvelopeExceedanceCount"] for row in summaries.values()),
            "inconclusiveTimingEnvelopes": sum(row["inconclusiveTimingEnvelopeCount"] for row in summaries.values()),
            "distanceExceedances": sum(row["distanceExceedanceCount"] for row in summaries.values()),
        },
        "limitations": plan["limitations"],
        "uncoveredIssueFamilies": ["stations", "seasons", "eclipses", "transits", "Jupiter moons", "Chiron", "complete physical uncertainty"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["acquire", "report", "check"])
    parser.add_argument("--binary", type=Path, default=BINARY)
    arguments = parser.parse_args()
    if arguments.action == "acquire":
        acquire()
        return
    report = assess(arguments.binary)
    data = encoded(report)
    if arguments.action == "report":
        if REPORT.exists():
            raise ValueError("planetary apsis report already frozen")
        REPORT.write_bytes(data)
        print(json.dumps(report["totals"], sort_keys=True))
    elif REPORT.read_bytes() != data:
        raise ValueError("planetary apsis report drift")
    else:
        print("Offline planetary apsis replay matched: " + json.dumps(report["totals"], sort_keys=True))


if __name__ == "__main__":
    main()
