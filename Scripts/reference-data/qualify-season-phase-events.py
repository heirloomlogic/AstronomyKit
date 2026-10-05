#!/usr/bin/env python3
"""Replay the frozen season and lunar-phase reference plan offline."""

import argparse
import datetime
import hashlib
import importlib.util
import json
import math
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "Documentation/Migration"
PLAN = DOCS / "season-phase-sampling-plan.json"
POLICY = DOCS / "approved-accuracy-targets.json"
REPORT = DOCS / "season-phase-assessment.json"
BINARY = ROOT / ".context/accuracy-qualification/build-runner/debug/AccuracyQualificationRunner"
BUILD_HELPER = Path(__file__).with_name("build-bundled-runner.py")
BUILD_SPEC = importlib.util.spec_from_file_location("bundled_runner", BUILD_HELPER)
BUILD = importlib.util.module_from_spec(BUILD_SPEC)
BUILD_SPEC.loader.exec_module(BUILD)


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def validate_plan(plan):
    if plan.get("schemaVersion") != 1:
        raise ValueError("season/phase plan schema changed")
    if plan.get("approvedPolicy") != {"path": str(POLICY.relative_to(ROOT)), "sha256": digest(POLICY.read_bytes())}:
        raise ValueError("season/phase plan detached from approved policy")
    if plan.get("comparison") != {
        "displayResolutionSeconds": 60,
        "referenceRoundingDirection": "not-recorded",
        "thresholdSeconds": 60,
        "timingRule": "strictlyLessThan",
    }:
        raise ValueError("season/phase strict comparison changed")
    if plan.get("domain", {}).get("approved") != {
        "startInclusiveTT": "1900-01-01T00:00:00",
        "stopExclusiveTT": "2131-01-01T00:00:00",
    }:
        raise ValueError("season/phase approved domain changed")
    if plan.get("expectedRetainedCounts") != {"lunarPhases": 1038, "seasons": 804}:
        raise ValueError("season/phase retained counts changed")
    for family in ("seasons", "lunarPhases"):
        source = plan.get("referenceSources", {}).get(family, {})
        path = ROOT / source.get("path", "")
        if not path.is_file() or source.get("sha256") != digest(path.read_bytes()):
            raise ValueError(f"season/phase source detached for {family}")
        if source.get("upstreamRevision") != "865d3da7d8112bbc7911238052c6af4aaf877181":
            raise ValueError(f"season/phase source revision changed for {family}")
        if "aa.usno.navy.mil/api/" not in source.get("sourceAPI", ""):
            raise ValueError(f"season/phase source query provenance missing for {family}")
    return plan


def load_plan():
    return validate_plan(json.loads(PLAN.read_bytes()))


def retained_years(plan, family):
    rule = plan["domain"][family]["retainedCalendarYears"]
    return list(range(rule["first"], rule["last"] + 1, rule["step"]))


def julian_date_ut(text):
    normalized = text.removesuffix("Z")
    value = datetime.datetime.fromisoformat(normalized).replace(tzinfo=datetime.timezone.utc)
    return value.timestamp() / 86_400 + 2_440_587.5


def parse_seasons(plan):
    source = ROOT / plan["referenceSources"]["seasons"]["path"]
    years = set(retained_years(plan, "seasons"))
    identities = {3: "marchEquinox", 6: "juneSolstice", 9: "septemberEquinox", 12: "decemberSolstice"}
    rows = []
    for line_number, line in enumerate(source.read_text().splitlines(), 1):
        timestamp, phenomenon = line.split()
        year = int(timestamp[:4])
        month = int(timestamp[5:7])
        if year in years and phenomenon in {"Equinox", "Solstice"}:
            rows.append({"kind": identities[month], "sourceLine": line_number, "sourceTime": timestamp, "julianDateUT": julian_date_ut(timestamp), "year": year})
    expected = plan["expectedRetainedCounts"]["seasons"]
    if len(rows) != expected:
        raise ValueError(f"season source retained {len(rows)} events; expected {expected}")
    expected_kinds = plan["referenceSources"]["seasons"]["eventIdentities"]
    for year in retained_years(plan, "seasons"):
        if [row["kind"] for row in rows if row["year"] == year] != expected_kinds:
            raise ValueError(f"season identity sequence changed for {year}")
    if any(a["julianDateUT"] >= b["julianDateUT"] for a, b in zip(rows, rows[1:])):
        raise ValueError("season source is not strictly ordered")
    return rows


def parse_lunar_phases(plan):
    source = ROOT / plan["referenceSources"]["lunarPhases"]["path"]
    years = set(retained_years(plan, "lunarPhases"))
    names = {0: "new", 1: "firstQuarter", 2: "full", 3: "lastQuarter"}
    rows = []
    for line_number, line in enumerate(source.read_text().splitlines(), 1):
        quarter, timestamp = line.split()
        year = int(timestamp[:4])
        if year in years:
            rows.append({"kind": names[int(quarter)], "sourceLine": line_number, "sourceTime": timestamp, "julianDateUT": julian_date_ut(timestamp), "year": year})
    expected = plan["expectedRetainedCounts"]["lunarPhases"]
    if len(rows) != expected:
        raise ValueError(f"lunar-phase source retained {len(rows)} events; expected {expected}")
    identities = plan["referenceSources"]["lunarPhases"]["eventIdentities"]
    indexes = {name: index for index, name in enumerate(identities)}
    for year in retained_years(plan, "lunarPhases"):
        year_rows = [row for row in rows if row["year"] == year]
        if any((indexes[b["kind"]] - indexes[a["kind"]]) % 4 != 1 for a, b in zip(year_rows, year_rows[1:])):
            raise ValueError(f"lunar-phase identity sequence changed for {year}")
    if any(a["julianDateUT"] >= b["julianDateUT"] for a, b in zip(rows, rows[1:])):
        raise ValueError("lunar-phase source is not strictly ordered")
    return rows


def nominal_within_target(error_seconds, threshold_seconds):
    return math.isfinite(error_seconds) and abs(error_seconds) < threshold_seconds


def compare_events(references, candidates, threshold_seconds):
    reference_order = all(math.isfinite(row.get("julianDateTT", math.nan)) for row in references) and all(a["julianDateTT"] < b["julianDateTT"] for a, b in zip(references, references[1:]))
    candidate_order = all(math.isfinite(row.get("julianDateTT", math.nan)) for row in candidates) and all(a["julianDateTT"] < b["julianDateTT"] for a, b in zip(candidates, candidates[1:]))
    rows = []
    failures = []
    for index in range(max(len(references), len(candidates))):
        reference = references[index] if index < len(references) else None
        candidate = candidates[index] if index < len(candidates) else None
        identity = reference is not None and candidate is not None and reference.get("kind") == candidate.get("kind")
        error = None
        within = False
        if reference is not None and candidate is not None and math.isfinite(reference.get("julianDateTT", math.nan)) and math.isfinite(candidate.get("julianDateTT", math.nan)):
            error = (candidate["julianDateTT"] - reference["julianDateTT"]) * 86_400
            within = identity and nominal_within_target(error, threshold_seconds)
        row = {
            "candidate": candidate,
            "identityMatches": identity,
            "nominalErrorSeconds": error,
            "nominalWithinTarget": within,
            "ordinal": index,
            "reference": reference,
        }
        rows.append(row)
        if not identity or not within:
            failures.append(row)
    count_matches = len(references) == len(candidates)
    kinds_match = count_matches and [row.get("kind") for row in references] == [row.get("kind") for row in candidates]
    if not count_matches:
        failures.append({"reason": "event counts differ", "referenceCount": len(references), "candidateCount": len(candidates)})
    if not reference_order:
        failures.append({"reason": "reference events are not finite and strictly ordered"})
    if not candidate_order:
        failures.append({"reason": "candidate events are not finite and strictly ordered"})
    return {
        "candidateOrderValid": candidate_order,
        "countMatches": count_matches,
        "failures": failures,
        "kindSequenceMatches": kinds_match,
        "referenceOrderValid": reference_order,
        "rows": rows,
    }


def mutation_controls(rows, threshold_seconds):
    wrong_scale_failures = 0
    wrong_scale_classification_changes = 0
    wrong_event_identity_failures = 0
    for index, row in enumerate(rows):
        reference = row["reference"]
        candidate = row["candidate"]
        if reference is None or candidate is None:
            continue
        wrong_scale_error = (candidate["julianDateTT"] - reference["julianDateUT"]) * 86_400
        wrong_scale_pass = nominal_within_target(wrong_scale_error, threshold_seconds)
        wrong_scale_failures += not wrong_scale_pass
        wrong_scale_classification_changes += wrong_scale_pass != row["nominalWithinTarget"]
        next_candidate = rows[(index + 1) % len(rows)]["candidate"]
        wrong_event_identity_failures += next_candidate is None or next_candidate["kind"] != reference["kind"]
    return {
        "eventSelectionShift": {
            "detected": wrong_event_identity_failures > 0,
            "identityFailureCount": wrong_event_identity_failures,
        },
        "sourceUTMisreadAsTT": {
            "classificationChangeCount": wrong_scale_classification_changes,
            "detected": wrong_scale_classification_changes > 0,
            "nominalFailureCount": wrong_scale_failures,
        },
        "strictBoundary": {"detected": not nominal_within_target(threshold_seconds, threshold_seconds)},
    }


def request_lines(requests, binary):
    process = subprocess.Popen([str(binary), "accuracy-batch"], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    stdout, stderr = process.communicate("".join(json.dumps(request, sort_keys=True) + "\n" for request in requests))
    if process.returncode != 0:
        raise ValueError(f"season/phase runner failed: {stderr.strip()}")
    responses = [json.loads(line) for line in stdout.splitlines()]
    if len(responses) != len(requests) or any(row.get("status") != "success" for row in responses):
        raise ValueError("season/phase runner returned incomplete or failed responses")
    return responses


def calendar_year_bounds(year):
    start = datetime.datetime(year, 1, 1, tzinfo=datetime.timezone.utc)
    stop = datetime.datetime(year + 1, 1, 1, tzinfo=datetime.timezone.utc)
    return start.timestamp() / 86_400 + 2_440_587.5, stop.timestamp() / 86_400 + 2_440_587.5


def family_assessment(plan, family, references, binary):
    years = retained_years(plan, family)
    grouped = {year: [dict(row) for row in references if row["year"] == year] for year in years}
    requests = []
    for year in years:
        source_rows = grouped[year]
        request = {"deltaTModel": "espenak-meeus", "referenceJulianDatesUT": [row["julianDateUT"] for row in source_rows]}
        if family == "seasons":
            request.update({"operation": "seasons", "year": year})
        else:
            start, stop = calendar_year_bounds(year)
            request.update({"operation": "lunar-phases", "startJulianDateUT": start, "stopJulianDateUT": stop})
        requests.append(request)
    responses = request_lines(requests, binary)
    year_results = []
    all_rows = []
    all_failures = []
    for year, response in zip(years, responses):
        source_rows = grouped[year]
        converted = response["referenceJulianDatesTT"]
        if len(converted) != len(source_rows):
            raise ValueError(f"reference time conversion count changed for {family} {year}")
        bound = [{**row, "julianDateTT": tt} for row, tt in zip(source_rows, converted)]
        compared = compare_events(bound, response["events"], plan["comparison"]["thresholdSeconds"])
        year_results.append({key: value for key, value in compared.items() if key not in {"rows", "failures"}} | {"year": year, "failureCount": len(compared["failures"])})
        all_rows.extend(compared["rows"])
        all_failures.extend({"year": year, **failure} for failure in compared["failures"])
    errors = [abs(row["nominalErrorSeconds"]) for row in all_rows if row["nominalErrorSeconds"] is not None]
    return {
        "candidateEventCount": sum(1 for row in all_rows if row["candidate"] is not None),
        "failureCount": len(all_failures),
        "failures": all_failures,
        "maximumAbsoluteNominalErrorSeconds": max(errors) if errors else None,
        "mutationControls": mutation_controls(all_rows, plan["comparison"]["thresholdSeconds"]),
        "nominalFailureCount": sum(not row["nominalWithinTarget"] for row in all_rows),
        "nominalPassCount": sum(row["nominalWithinTarget"] for row in all_rows),
        "referenceEventCount": len(references),
        "rows": all_rows,
        "yearResults": year_results,
    }


def input_hashes():
    paths = [
        PLAN,
        POLICY,
        Path(__file__),
        BUILD_HELPER,
        Path(BUILD.builder.__file__),
        ROOT / "Tools/Migration/AccuracyQualificationRunner/main.swift",
        ROOT / "Scripts/reference-data/sources/seasons.txt",
        ROOT / "Scripts/reference-data/sources/moonphases.txt",
        ROOT / "Scripts/reference-data/sources/parse-moon-phases.js",
    ]
    return {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in paths}


def git_receipt():
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
    return revision, dirty


def build_report(binary=BINARY):
    plan = load_plan()
    build = BUILD.validate(binary)
    seasons = family_assessment(plan, "seasons", parse_seasons(plan), binary)
    phases = family_assessment(plan, "lunarPhases", parse_lunar_phases(plan), binary)
    revision, dirty = git_receipt()
    return {
        "candidateDirty": dirty,
        "candidateRevision": revision,
        "classification": "finite-archived-reference-comparison-not-continuous-certification",
        "coverage": plan["domain"],
        "executableReceipt": build,
        "families": {"lunarPhases": phases, "seasons": seasons},
        "inputSHA256": input_hashes(),
        "planSHA256": digest(PLAN.read_bytes()),
        "referencePrecision": {
            "displayResolutionSeconds": plan["comparison"]["displayResolutionSeconds"],
            "physicalStrictTargetQualification": "indeterminate-without-recorded-rounding-direction",
            "roundingDirection": plan["comparison"]["referenceRoundingDirection"],
        },
        "schemaVersion": 1,
        "timingTarget": plan["comparison"],
    }


def scientific_report(report):
    return {key: value for key, value in report.items() if key not in {"candidateDirty", "candidateRevision"}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("report", "check"))
    parser.add_argument("--binary", type=Path, default=BINARY)
    args = parser.parse_args()
    report = build_report(args.binary)
    if args.action == "report":
        REPORT.write_bytes(encoded(report))
    else:
        if not REPORT.exists() or scientific_report(json.loads(REPORT.read_bytes())) != scientific_report(report):
            raise ValueError(f"season/phase assessment is stale: {REPORT}")
    totals = {family: {"references": data["referenceEventCount"], "nominalPasses": data["nominalPassCount"], "nominalFailures": data["nominalFailureCount"]} for family, data in report["families"].items()}
    print(json.dumps(totals, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, TypeError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(f"error: {error}")
