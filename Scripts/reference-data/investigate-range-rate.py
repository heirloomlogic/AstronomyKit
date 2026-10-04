#!/usr/bin/env python3
"""Replay sampled radial-rate diagnostics without introducing an accuracy allowance."""

import argparse
import sys
import hashlib
import importlib.util
import json
import math
import platform
import subprocess
import tempfile
from pathlib import Path
import source_archive

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("distance_archive", Path(__file__).with_name("distance-accuracy.py"))
DISTANCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DISTANCE)
REPORT = ROOT / "Documentation/Migration/range-rate-investigation.json"
PROBE = Path(__file__).with_name("range-rate-probe.c")
AU_KM = 149597870.7
C_AUDAY = 299792.458 * 86400 / AU_KM
STATUS = "sampled-diagnostic-without-accuracy-allowance"


def radial(position, velocity):
    if len(position) != 3 or len(velocity) != 3 or not all(math.isfinite(v) for v in position + velocity):
        raise ValueError("invalid Cartesian state")
    length = math.hypot(*position)
    if length == 0:
        raise ValueError("zero radius has no radial direction")
    return sum(p * v for p, v in zip(position, velocity)) / length


def to_kms(rate):
    return rate * AU_KM / 86400


def validate_projection(row):
    # A table-rounding integrity check, not an allowance for the astronomical model.
    if not math.isfinite(row["rangeRateAUPerDay"]) or abs(radial(row["positionAU"], row["velocityAUPerDay"]) - row["rangeRateAUPerDay"]) > 1e-14:
        raise ValueError("range-rate column disagrees with signed vector projection")


def classification(body, mode, correction, scale):
    if scale != "TT":
        raise ValueError("TT epoch alignment required; TDB must not be relabelled TT")
    if mode == "heliocentric" or body == "Moon":
        if correction != "NONE":
            raise ValueError("geometric observable requires NONE reference correction")
        return "geometric-state-matched"
    if mode != "geocentric" or correction != "LT":
        raise ValueError("unexpected observer/correction convention")
    return "received-light-unmatched-derivative-and-origin"


def received_velocity(position, target_velocity, observer_velocity, c=C_AUDAY):
    length = math.hypot(*position)
    unit = [value / length for value in position]
    a = sum(u * v for u, v in zip(unit, target_velocity)) / c
    b = sum(u * v for u, v in zip(unit, observer_velocity)) / c
    factor = (1 + b) / (1 + a)
    return [v * factor - o for v, o in zip(target_velocity, observer_velocity)], factor


def fixed_sun_bridge(position, velocity, sun_emission_position, sun_reception_position,
                     sun_emission_velocity, sun_reception_velocity, emission_factor):
    return ([p - e + r for p, e, r in zip(position, sun_emission_position, sun_reception_position)],
            [v - e * emission_factor + r for v, e, r in zip(velocity, sun_emission_velocity, sun_reception_velocity)])


def references():
    records, provenance = [], {}
    for phase in ("characterization", "heldout"):
        for body, mode in DISTANCE.series():
            name = f"{body.lower()}-{mode}"
            rows, metadata = DISTANCE.read_pair(DISTANCE.RAW / phase, name, DISTANCE.query(body, mode, DISTANCE.epochs(phase)))
            category = classification(body, mode, metadata["correction"], metadata["timeScale"])
            provenance[f"{phase}/{name}"] = metadata
            for row in rows:
                validate_projection(row)
                records.append({"phase": phase, "body": body, "mode": mode, "julianDateTT": row["julianDateTT"],
                                "classification": category, "timeDerivativeScaleMatchEstablished": False, "reference": row})
    return records, provenance


def sun_velocity_evidence():
    cases = []
    for phase in ("characterization", "heldout"):
        dates = DISTANCE.epochs(phase)
        directory = DISTANCE.RAW / phase
        rows, _ = DISTANCE.read_pair(directory, "sun-geocentric", DISTANCE.query("Sun", "geocentric", dates))
        earth, _ = DISTANCE.read_pair(directory, "earth-heliocentric", DISTANCE.query("Earth", "heliocentric", dates))
        sun_dates = sorted(set(dates + [round(r["julianDateTT"] - r["lightTimeDays"], 8) for r in rows]))
        sun, _ = DISTANCE.read_pair(directory, "sun-geocentric-sun", DISTANCE.query("Sun", "heliocentric", sun_dates, sun=True))
        earth_by_date = {round(r["julianDateTT"], 8): r for r in earth}
        sun_by_date = {round(r["julianDateTT"], 8): r for r in sun}
        for row in rows:
            jd = row["julianDateTT"]
            now = sun_by_date[round(jd, 8)]
            then = sun_by_date[round(jd - row["lightTimeDays"], 8)]
            observer_velocity = [a + b for a, b in zip(earth_by_date[round(jd, 8)]["velocityAUPerDay"], now["velocityAUPerDay"])]
            target_velocity = then["velocityAUPerDay"]
            raw_velocity = [a - b for a, b in zip(target_velocity, observer_velocity)]
            derivative, factor = received_velocity(row["positionAU"], target_velocity, observer_velocity)
            cases.append({"phase": phase, "julianDateTT": jd, "emissionJulianDateTTRounded": then["julianDateTT"],
                          "observerBarycentricVelocityAUPerDay": observer_velocity, "targetEmissionVelocityAUPerDay": target_velocity,
                          "archivedVelocityAUPerDay": row["velocityAUPerDay"], "rawRelativeVelocityAUPerDay": raw_velocity,
                          "receptionDerivativeVelocityAUPerDay": derivative, "emissionDerivativeFactor": factor,
                          "rawVelocityResidualKmPerSecond": to_kms(math.dist(raw_velocity, row["velocityAUPerDay"])),
                          "chainVelocityResidualKmPerSecond": to_kms(math.dist(derivative, row["velocityAUPerDay"]))})
    return {"classification": "Sun-only-archived-retarded-velocity-inference", "cases": cases,
            "maximumRawVelocityResidualKmPerSecond": max(r["rawVelocityResidualKmPerSecond"] for r in cases),
            "maximumChainVelocityResidualKmPerSecond": max(r["chainVelocityResidualKmPerSecond"] for r in cases),
            "limits": "Same archived ephemeris endpoints; emission TT rounded to 1e-8 day. This inference does not establish other targets, exact derivative time scale, or an astronomical accuracy allowance."}


def input_hashes():
    paths = [Path(__file__), PROBE, Path(__file__).with_name("distance-accuracy.py")]
    paths += sorted((ROOT / "Sources/CLibAstronomy").rglob("*.c"))
    paths += sorted((ROOT / "Sources/CLibAstronomy").rglob("*.h"))
    paths += sorted((ROOT / "Sources/CLibAstronomy").rglob("*.inc"))
    for phase in ("characterization", "heldout"):
        paths += sorted((DISTANCE.RAW / phase).glob("*.json"))
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def measure(records):
    with tempfile.TemporaryDirectory(prefix="range-rate-") as temporary:
        binary = Path(temporary) / "probe"
        command = ["cc", "-O2", "-std=c11", "-pthread", "-fno-fast-math", "-ffp-contract=off", "-I", str(ROOT / "Sources/CLibAstronomy/include"),
                   str(PROBE), *map(str, sorted((ROOT / "Sources/CLibAstronomy").rglob("*.c"))), "-lm", "-o", str(binary)]
        subprocess.run(command, check=True)
        inputs = "".join(f"{r['body']} {r['mode']} {r['julianDateTT'] - 2451545:.17g}\n" for r in records)
        output = subprocess.check_output([str(binary)], input=inputs, text=True)
    values = [json.loads(line) for line in output.splitlines()]
    if len(values) != len(records):
        raise ValueError("probe coverage differs from reference coverage")
    return values, command


def build_report(revision=None):
    before = input_hashes()
    records, provenance = references()
    values, command = measure(records)
    for row, value in zip(records, values):
        row["production"] = value
        row["referenceRateKmPerSecond"] = to_kms(row["reference"]["rangeRateAUPerDay"])
        row["productionRateKmPerSecond"] = to_kms(value["rateAUPerTTDay"])
        row["signedResidualKmPerSecond"] = row["productionRateKmPerSecond"] - row["referenceRateKmPerSecond"]
        row["localDerivativeResidualKmPerSecond"] = to_kms(value["rateAUPerTTDay"] - value["centralDifferenceSmall"])
        row["localDifferenceStepSensitivityKmPerSecond"] = to_kms(value["centralDifferenceSmall"] - value["centralDifferenceLarge"])
        row["stellarAberrationRateChangeKmPerSecond"] = to_kms(value["correctedRateAUPerTTDay"] - value["rateAUPerTTDay"]) if row["mode"] == "geocentric" else None
    sun_evidence = sun_velocity_evidence()
    if before != input_hashes():
        raise ValueError("inputs changed during measurement")
    groups = {}
    for row in records:
        key = row["body"] + "/" + row["mode"]
        group = groups.setdefault(key, {"classification": row["classification"], "count": 0, "maximumAbsoluteResidualKmPerSecond": 0,
                                        "maximumLocalDerivativeResidualKmPerSecond": 0, "maximumStepSensitivityKmPerSecond": 0})
        group["count"] += 1
        for output, field in [("maximumAbsoluteResidualKmPerSecond", "signedResidualKmPerSecond"),
                              ("maximumLocalDerivativeResidualKmPerSecond", "localDerivativeResidualKmPerSecond"),
                              ("maximumStepSensitivityKmPerSecond", "localDifferenceStepSensitivityKmPerSecond")]:
            group[output] = max(group[output], abs(row[field]))
    return {"schemaVersion": 1, "status": STATUS, "accuracyAllowance": None,
            "workingTreeDirtyAtMeasurement": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
            "repositoryRevisionAtMeasurement": revision or subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            "inputSHA256": before, "provenance": provenance, "results": records, "groups": groups,
            "sunVelocityConventionEvidence": sun_evidence,
            "primarySources": [{"url": "https://ssd.jpl.nasa.gov/horizons/manual.html#obsquan", "scope": "Observer quantity20 sign and units; not a VECTORS reception-derivative guarantee."},
                               {"url": "https://ssd.jpl.nasa.gov/dat/horizons_news.txt", "scope": "Aug25,2007 Version3.32 change concerns observer quantities19/20; Aug30,2013 concerns LADEE, not this convention."},
                               {"url": "https://naif.jpl.nasa.gov/pub/naif/toolkit_docs/C/cspice/spkezr_c.html", "scope": "SPICE added the light-time derivative in Dec27,2007; this contract must not be transferred to Horizons."}],
            "environment": {"compiler": subprocess.check_output(["cc", "--version"], text=True).splitlines()[0], "python": platform.python_version(), "platform": platform.platform()},
            "probeBuildCommand": command, "localDifferenceStepsTTDays": [.001, .002],
            "timeConvention": "Horizons epoch labels are TT but ephemeris velocities follow its internal dynamical convention; unresolved TT/TDB rate scaling is retained as a limitation.",
            "unmatchedConvention": "LT rates are reported without claiming the public fixed-Sun reception derivative matches Horizons velocities or observer range-rate projections.",
            "limits": ["No rate accuracy threshold or continuous bound.", "Geometric matching identifies observable/origin/epoch, not proven TT/TDB derivative equivalence.",
                       "Moon uses instantaneous geometric series with a short central-difference velocity.", "Pluto interpolation and model-center discrepancies remain distinct from local derivative consistency."]}


def validate_report(report):
    if report.get("status") != STATUS or report.get("accuracyAllowance") is not None:
        raise ValueError("diagnostic report cannot adopt an accuracy threshold")
    if report.get("inputSHA256") != input_hashes():
        raise ValueError("report inputs are stale")
    if len(report.get("results", [])) != 5035:
        raise ValueError("complete archived population required")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--output", type=Path, default=REPORT)
    arguments = parser.parse_args()
    if __name__ == "__main__" and "--check" in sys.argv[1:]:
        source_archive.replay(ROOT, Path(__file__), sys.argv[1:])
        return
    if arguments.check:
        old = json.loads(arguments.output.read_text())
        validate_report(old)
        new = build_report(old["repositoryRevisionAtMeasurement"])
        # Compiler/platform provenance remains historical; numerical rows are replayed offline.
        if old["results"] != new["results"] or old["groups"] != new["groups"] or old["provenance"] != new["provenance"] or old["sunVelocityConventionEvidence"] != new["sunVelocityConventionEvidence"]:
            raise ValueError("offline numerical replay differs from archived report")
    else:
        if arguments.output.exists():
            raise ValueError("refusing to overwrite historical rate evidence")
        report = build_report()
        validate_report(report)
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_bytes(DISTANCE.encoded(report))
    print(json.dumps({"status": STATUS, "cases": 5035, "accuracyAllowance": None}, sort_keys=True))


if __name__ == "__main__":
    main()
