#!/usr/bin/env python3
"""Separate independent characterization, policy freezing, and held-out acceptance."""

import argparse
import sys
import csv
import hashlib
import json
import math
import random
import re
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path
import source_archive

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "Scripts/reference-data/sources/distance"
DOCS = ROOT / "Documentation/Migration"
CHARACTERIZATION = DOCS / "distance-characterization.json"
BUDGET = DOCS / "distance-allowances.json"
FIXTURE = ROOT / "Tests/AstronomyKitTests/Fixtures/IndependentReferences/distance-fixtures.json"
REPORT = DOCS / "distance-acceptance.json"
AU_KM = 149597870.7
API = "https://ssd.jpl.nasa.gov/api/horizons_file.api"
START, STOP = 2415020.5, 2488434.5  # 1900-01-01 through 2101-01-01 TT (exclusive).
BODIES = {"Mercury": "199", "Venus": "299", "Earth": "399", "Mars": "499",
          "Jupiter": "599", "Saturn": "699", "Uranus": "799", "Neptune": "899",
          "Pluto": "999", "Moon": "301", "Sun": "10"}
LITERATURE_KM = {"Mercury": .347, "Venus": 2.705, "Earth": 3.740, "Mars": 22.794,
                 "Jupiter": 272.404, "Saturn": 1000.554, "Uranus": 229.999, "Neptune": 1891.819}


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def epochs(phase):
    rng = random.Random(8101 if phase == "characterization" else 8102)
    # One randomly placed epoch in each of 128 equal date strata; no engine-guided selection.
    values = [round(START + (i + rng.random()) * (STOP - START) / 128, 8) for i in range(128)]
    if phase == "characterization":
        values += [START, STOP - 1 / 86400, 2451545.0]
    else:
        # Transits, opposition, station, and lunar apsis leads selected before characterization.
        values += [2453164.5, 2457517.5, 2459135.5, 2460898.5, 2458863.5, 2458878.5]
    return sorted(set(values))


def series():
    for body in BODIES:
        if body not in ("Moon", "Sun"):
            yield body, "heliocentric"
        if body != "Earth":
            yield body, "geocentric"


def query(body, mode, dates, sun=False):
    parameters = {
        "COMMAND": BODIES[body], "OBJ_DATA": "NO", "MAKE_EPHEM": "YES",
        "EPHEM_TYPE": "VECTORS", "CENTER": "500@0" if sun else "500@10" if mode == "heliocentric" else "500@399",
        "TLIST": ",".join(format(jd, ".8f") for jd in dates), "TLIST_TYPE": "JD",
        "TIME_TYPE": "TT", "REF_SYSTEM": "ICRF", "REF_PLANE": "FRAME",
        "OUT_UNITS": "AU-D", "VEC_TABLE": "3", "VEC_CORR": "LT" if mode == "geocentric" and body != "Moon" and not sun else "NONE",
        "CSV_FORMAT": "YES", "CAL_TYPE": "GREGORIAN",
    }
    return {key: f"'{value}'" for key, value in parameters.items()}


def download(parameters):
    lines = ["!$$SOF"]
    for key, value in parameters.items():
        if key == "TLIST":
            lines.append("TLIST=" + "\n".join(f"'{jd}'" for jd in value.strip("'").split(",")))
        else:
            lines.append(f"{key}={value}")
    file_data = "\n".join(lines) + "\n"
    boundary = "AstronomyKitDistanceReferenceBoundary"
    payload = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"format\"\r\n\r\njson\r\n"
               f"--{boundary}\r\nContent-Disposition: form-data; name=\"input\"; filename=\"query.txt\"\r\n"
               f"Content-Type: text/plain\r\n\r\n{file_data}\r\n--{boundary}--\r\n").encode()
    for attempt in range(3):
        try:
            request = urllib.request.Request(API, data=payload, headers={"User-Agent": "AstronomyKit distance characterization",
                                             "Content-Type": f"multipart/form-data; boundary={boundary}"})
            with urllib.request.urlopen(request, timeout=45) as response:
                data = response.read()
            parse_response(data, parameters)
            return data
        except (OSError, ValueError) as error:
            if attempt == 2:
                raise RuntimeError(f"Horizons acquisition failed: {error}") from error
            time.sleep(1 << attempt)


def parse_response(data, parameters):
    envelope = json.loads(data)
    text = envelope.get("result", "")
    if "error" in envelope or "$$SOE" not in text or "$$EOE" not in text:
        raise ValueError("Horizons response has no complete ephemeris")
    if envelope.get("signature") != {"source": "NASA/JPL Horizons API", "version": "1.0"}:
        raise ValueError("unrecognized Horizons file API version")
    target = re.search(r"Target body name:\s*(.*?)\s+\{source:\s*([^}]+)\}", text)
    center = re.search(r"Center body name:\s*(.*?)\s+\{source:\s*([^}]+)\}", text)
    if not target or not center:
        raise ValueError("missing source/center identification")
    command = parameters["COMMAND"].strip("'")
    center_code = parameters["CENTER"].strip("'").split("@")[-1]
    if f"({command})" not in target[1] or f"({center_code})" not in center[1]:
        raise ValueError("target or origin differs from recipe")
    if "JDTT" not in text or "Reference frame : ICRF" not in text or "Output units    : AU-D" not in text:
        raise ValueError("time scale, frame, or units differ from recipe")
    correction = parameters["VEC_CORR"].strip("'")
    expected = "GEOMETRIC" if correction == "NONE" else "LT CORRECTED"
    if not re.search(r"Output type\s*:\s*" + expected, text):
        raise ValueError("corrections differ from recipe")
    rows = []
    for fields in csv.reader(text.split("$$SOE", 1)[1].split("$$EOE", 1)[0].strip().splitlines()):
        values = [float(fields[0])] + [float(value) for value in fields[2:11]]
        if len(values) != 10 or not all(math.isfinite(value) for value in values):
            raise ValueError("invalid state row")
        rows.append({"julianDateTT": values[0], "positionAU": values[1:4], "velocityAUPerDay": values[4:7],
                     "lightTimeDays": values[7], "rangeAU": values[8], "rangeRateAUPerDay": values[9]})
        if values[8] <= 0 or abs(math.hypot(*values[1:4]) - values[8]) > 1e-11:
            raise ValueError("range and vector units are inconsistent")
    requested = [float(value) for value in parameters["TLIST"].strip("'").split(",")]
    if len(rows) != len(requested) or any(abs(row["julianDateTT"] - jd) > 1e-8 for row, jd in zip(rows, sorted(requested))):
        raise ValueError("epoch coverage differs from recipe")
    return rows, {"target": target[1], "targetEphemeris": target[2], "center": center[1], "centerEphemeris": center[2],
                  "service": envelope["signature"], "frame": "ICRF", "timeScale": "TT", "units": "AU-D", "correction": correction,
                  "url": API, "license": "US government JPL ephemeris output; no AstronomyKit-generated reference values"}


def archive_pair(directory, name, parameters):
    data = download(parameters)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{name}.json").write_bytes(data)
    (directory / f"{name}.query.json").write_bytes(encoded({"parameters": parameters, "responseSHA256": digest(data)}))
    return parse_response(data, parameters)[0]


def read_pair(directory, name, expected=None):
    recipe = json.loads((directory / f"{name}.query.json").read_bytes())
    data = (directory / f"{name}.json").read_bytes()
    if recipe["responseSHA256"] != digest(data) or (expected is not None and recipe["parameters"] != expected):
        raise ValueError("response hash or query recipe mismatch")
    return parse_response(data, recipe["parameters"])


def refresh(phase):
    if phase == "characterization" and BUDGET.exists():
        raise ValueError("characterization archive is frozen")
    if phase == "heldout" and not BUDGET.exists():
        raise ValueError("freeze allowances before acquiring held-out data")
    directory = RAW / phase
    dates = epochs(phase)
    for body, mode in series():
        name = f"{body.lower()}-{mode}"
        rows = archive_pair(directory, name, query(body, mode, dates))
        if mode == "geocentric" and body != "Moon":
            # Independent Sun endpoints expose the fixed-heliocentric-origin convention separately.
            sun_dates = sorted(set(dates + [round(row["julianDateTT"] - row["lightTimeDays"], 8) for row in rows]))
            archive_pair(directory, name + "-sun", query("Sun", "heliocentric", sun_dates, sun=True))
        print(f"archived {phase}/{name}", flush=True)


def references(phase):
    records, provenance = [], {}
    directory = RAW / phase
    dates = epochs(phase)
    for body, mode in series():
        name = f"{body.lower()}-{mode}"
        rows, metadata = read_pair(directory, name, query(body, mode, dates))
        provenance[name] = metadata
        sun_by_date = None
        if mode == "geocentric" and body != "Moon":
            sun_dates = sorted(set(dates + [round(row["julianDateTT"] - row["lightTimeDays"], 8) for row in rows]))
            sun_rows, sun_metadata = read_pair(directory, name + "-sun", query("Sun", "heliocentric", sun_dates, sun=True))
            sun_by_date = {round(row["julianDateTT"], 8): row for row in sun_rows}
            provenance[name + "-sun"] = sun_metadata
        for row in rows:
            p = row["positionAU"]
            reference = math.hypot(*p)
            convention = 0.0
            alignment_estimate = 0.0
            if sun_by_date is not None:
                now = sun_by_date[round(row["julianDateTT"], 8)]
                then = sun_by_date[round(row["julianDateTT"] - row["lightTimeDays"], 8)]
                p = [v - (a - b) for v, a, b in zip(p, then["positionAU"], now["positionAU"])]
                adjusted = math.hypot(*p)
                convention = (adjusted - reference) * AU_KM
                reference = adjusted
                # A posteriori first-order estimate, not a rigorous inequality: range change / c times target speed.
                speed_kms = math.hypot(*row["velocityAUPerDay"]) * AU_KM / 86400 + 60
                alignment_estimate = abs(convention) / 299792.458 * speed_kms
            records.append({"body": body, "mode": mode, "julianDateTT": row["julianDateTT"],
                            "referencePositionAU": p, "referenceRangeAU": reference,
                            "horizonsRangeAU": row["rangeAU"], "fixedSunConventionAdjustmentKm": convention,
                            "alignmentRemainderEstimateKm": alignment_estimate})
    return records, provenance


def input_hashes(phase):
    paths = [Path(__file__), ROOT / "Scripts/reference-data/distance-probe.c"]
    paths += sorted((ROOT / "Sources/CLibAstronomy").rglob("*.c"))
    paths += sorted((ROOT / "Sources/CLibAstronomy").rglob("*.h"))
    paths += sorted((ROOT / "Sources/CLibAstronomy").rglob("*.inc"))
    paths += sorted((RAW / phase).glob("*.json"))
    return {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in paths}


def measure(records):
    with tempfile.TemporaryDirectory(prefix="astronomykit-distance-") as directory:
        binary = Path(directory) / "probe"
        subprocess.run(["cc", "-O2", "-std=c11", "-pthread", "-I", str(ROOT / "Sources/CLibAstronomy/include"),
                        str(ROOT / "Scripts/reference-data/distance-probe.c"), *map(str, sorted(p for p in (ROOT / "Sources/CLibAstronomy").rglob("*.c") if p.name != "astronomy.c")), "-lm", "-o", str(binary)], check=True)
        inputs = "".join(f"{row['body']} {row['mode']} {row['julianDateTT'] - 2451545:.17g}\n" for row in records)
        output = subprocess.check_output([str(binary)], input=inputs, text=True)
    actuals = [json.loads(line) for line in output.splitlines()]
    if len(actuals) != len(records):
        raise ValueError("probe coverage mismatch")
    measured = []
    for row, actual in zip(records, actuals):
        difference = (actual["rangeAU"] - row["referenceRangeAU"]) * AU_KM
        measured.append({**row, "actualRangeAU": actual["rangeAU"], "signedRangeErrorKm": difference,
                         "vectorResidualKm": math.hypot(*(a-b for a, b in zip(actual["positionAU"], row["referencePositionAU"]))) * AU_KM,
                         "approximationDifferenceKm": actual["approximationDifferenceAU"] * AU_KM})
    return measured


def characterize():
    if BUDGET.exists():
        raise ValueError("characterization is frozen; do not regenerate it to erase acceptance failures")
    records, provenance = references("characterization")
    results = measure(records)
    summary = {}
    for body, mode in series():
        selected = [row for row in results if (row["body"], row["mode"]) == (body, mode)]
        summary[f"{body.lower()}-{mode}"] = {
            "samples": len(selected), "maximumRangeErrorKm": max(abs(row["signedRangeErrorKm"]) for row in selected),
            "worstJulianDateTT": max(selected, key=lambda row: abs(row["signedRangeErrorKm"]))["julianDateTT"],
            "p95RangeErrorKm": sorted(abs(row["signedRangeErrorKm"]) for row in selected)[math.ceil(.95 * len(selected)) - 1],
            "minimumReferenceRangeAU": min(row["referenceRangeAU"] for row in selected),
            "maximumReferenceRangeAU": max(row["referenceRangeAU"] for row in selected),
            "maximumVectorResidualKm": max(row["vectorResidualKm"] for row in selected),
            "maximumApproximationDifferenceKm": max(row["approximationDifferenceKm"] for row in selected),
            "maximumConventionAdjustmentKm": max(abs(row["fixedSunConventionAdjustmentKm"]) for row in selected),
            "maximumAlignmentRemainderEstimateKm": max(row["alignmentRemainderEstimateKm"] for row in selected),
        }
    report = {"schemaVersion": 1, "classification": "empirical-characterization-not-certified-bound",
              "inputSHA256": input_hashes("characterization"), "provenance": provenance,
              "summary": summary, "results": results}
    CHARACTERIZATION.write_bytes(encoded(report))
    print(json.dumps(summary, indent=2))


def freeze():
    if BUDGET.exists():
        raise ValueError("allowances already frozen")
    report = json.loads(CHARACTERIZATION.read_bytes())
    if report["inputSHA256"] != input_hashes("characterization"):
        raise ValueError("stale characterization")
    allowances = {}
    for body, mode in series():
        key = f"{body.lower()}-{mode}"
        row = report["summary"][key]
        # Published scales are context/floors; the 2x margin is explicit project policy.
        floor = LITERATURE_KM.get(body, LITERATURE_KM["Earth"] if body == "Sun" else 0)
        if mode == "geocentric" and body not in ("Moon", "Sun"):
            floor += LITERATURE_KM["Earth"]
        alignment = 1.0 if mode == "geocentric" and body != "Moon" else 0.0
        if row["maximumAlignmentRemainderEstimateKm"] > alignment or row["maximumApproximationDifferenceKm"] > .001:
            raise ValueError("separate implementation/alignment allowance is insufficient")
        value = 2 * max(floor, row["maximumRangeErrorKm"]) + .001 + alignment
        allowances[key] = {"body": body, "mode": mode, "allowedErrorKm": math.ceil(value * 1000) / 1000,
                           "literatureScaleFloorKm": floor, "characterizationMaximumKm": row["maximumRangeErrorKm"],
                           "approximationAllowanceKm": .001, "alignmentAllowanceKm": alignment}
    BUDGET.write_bytes(encoded({"schemaVersion": 1, "classification": "finite-fixture-engineering-allowance-not-sky-error-bound",
                               "policy": "2 * max(characterization maximum, literature scale floor) + approximation allowance + alignment allowance; round upward to 0.001 km",
                               "marginMultiplier": 2, "domain": "1900-01-01 <= TT < 2101-01-01",
                               "characterizationSHA256": digest(CHARACTERIZATION.read_bytes()), "allowances": allowances}))
    print("froze body-specific allowances before held-out evaluation")


def acceptance(check=False):
    budget_bytes = BUDGET.read_bytes()
    budget = json.loads(budget_bytes)
    if budget["characterizationSHA256"] != digest(CHARACTERIZATION.read_bytes()):
        raise ValueError("characterization changed after allowances were frozen")
    characterization = json.loads(CHARACTERIZATION.read_bytes())
    if characterization["inputSHA256"] != input_hashes("characterization"):
        raise ValueError("characterization inputs changed; historical policy needs explicit review")
    records, provenance = references("heldout")
    fixture = {"schemaVersion": 1, "allowancesSHA256": digest(budget_bytes), "provenance": provenance,
               "references": [{**row, "allowedErrorKm": budget["allowances"][f"{row['body'].lower()}-{row['mode']}"]["allowedErrorKm"]} for row in records]}
    results = measure(fixture["references"])
    failures = [row for row in results if abs(row["signedRangeErrorKm"]) > row["allowedErrorKm"] or row["alignmentRemainderEstimateKm"] > (0 if row["body"] == "Moon" or row["mode"] == "heliocentric" else 1)]
    report = {"schemaVersion": 1, "classification": "sampled-held-out-acceptance-not-continuous-certification",
              "allowancesSHA256": digest(budget_bytes), "inputSHA256": input_hashes("heldout"),
              "fixtureSHA256": digest(encoded(fixture)), "sampleCount": len(results), "failureCount": len(failures),
              "results": results}
    report["summary"] = {}
    for body, mode in series():
        key = f"{body.lower()}-{mode}"
        selected = [row for row in results if (row["body"], row["mode"]) == (body, mode)]
        worst = max(selected, key=lambda row: abs(row["signedRangeErrorKm"]))
        report["summary"][key] = {"samples": len(selected), "maximumRangeErrorKm": abs(worst["signedRangeErrorKm"]),
                                  "worstJulianDateTT": worst["julianDateTT"], "allowedErrorKm": worst["allowedErrorKm"],
                                  "failures": sum(abs(row["signedRangeErrorKm"]) > row["allowedErrorKm"] for row in selected)}
    if check:
        if FIXTURE.read_bytes() != encoded(fixture) or REPORT.read_bytes() != encoded(report):
            raise ValueError("distance fixture or acceptance evidence is stale")
    else:
        FIXTURE.write_bytes(encoded(fixture))
        REPORT.write_bytes(encoded(report))
    print(f"{len(results)} held-out comparisons; {len(failures)} failures")
    if failures:
        raise ValueError("held-out acceptance failed; retain frozen policy and investigate")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["refresh-characterization", "characterize", "freeze", "refresh-heldout", "accept", "check"])
    action = parser.parse_args().action
    if __name__ == "__main__" and action == "check":
        source_archive.replay(ROOT, Path(__file__), sys.argv[1:])
        return
    if action.startswith("refresh-"):
        refresh(action.removeprefix("refresh-"))
    elif action == "characterize":
        characterize()
    elif action == "freeze":
        freeze()
    else:
        acceptance(check=action == "check")


if __name__ == "__main__":
    main()
