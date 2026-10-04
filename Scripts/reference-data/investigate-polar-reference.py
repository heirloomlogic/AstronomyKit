#!/usr/bin/env python3
"""Archive and replay independent polar horizon comparisons; no accuracy gate."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import importlib.util
import json
import math
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT / "Scripts/reference-data/sources/polar-reference"
DIAGNOSIS = ROOT / "Documentation/Migration/polar-sunrise-diagnosis.json"
REPORT = ROOT / "Documentation/Migration/polar-reference-comparison.json"
HORIZONS = "https://ssd.jpl.nasa.gov/api/horizons.api"
USNO = "https://aa.usno.navy.mil/api/rstt/oneday"
ORIGIN = dt.datetime(2000, 1, 1, 12)
CASES = (
    (2922, -90, "2022-03-22", "S", "18:07"),
    (2923, -90, "2022-09-20", "R", "21:52"),
    (5908, 90, "2022-03-18", "R", "13:02"),
    (5909, 90, "2022-09-25", "S", "04:13"),
)


def encoded(value):
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def model_report():
    # Reuse the existing source bindings without changing the production core.
    spec = importlib.util.spec_from_file_location("polar_diagnosis", ROOT / "Scripts/reference-data/diagnose-polar-sunrise.py")
    diag = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(diag)
    for path, digest in {
        diag.CURRENT_SOURCE: diag.CURRENT_SOURCE_SHA256,
        diag.CURRENT_HEADER: diag.CURRENT_HEADER_SHA256,
        diag.PINNED_SOURCE: diag.PINNED_SOURCE_SHA256,
        diag.PINNED_HEADER: diag.PINNED_HEADER_SHA256,
        diag.RISE_SET_SOURCE: diag.RISE_SET_SOURCE_SHA256,
        **diag.CURRENT_ASSETS,
    }.items():
        diag.read_verified_source(path, digest)
    report = json.loads(DIAGNOSIS.read_text())
    diag.validate_report(report)
    return report


def events(report, name):
    return {e["sourceLine"]: e for e in report["variants"][name]["events"]}


def horizons_parameters(line, latitude, report):
    event = events(report, "current")[line]
    # TT is explicit: do not transfer Espenak-Meeus UT labels to JPL UTC.
    epochs = [event["expectedTT"] + seconds / 86400 for seconds in range(-600, 601, 30)]
    epochs += [events(report, name)[line]["eventTT"] for name in ("current", "pinned")]
    return {
        "format": "json", "COMMAND": "'10'", "OBJ_DATA": "'NO'",
        "EPHEM_TYPE": "'OBSERVER'", "CENTER": "'coord@399'",
        "COORD_TYPE": "'GEODETIC'", "SITE_COORD": f"'0,{latitude},0'",
        "TLIST": "'" + ",".join(f"{2451545 + t:.12f}" for t in sorted(epochs)) + "'",
        "TIME_TYPE": "'TT'", "CAL_FORMAT": "'BOTH'", "CAL_TYPE": "'GREGORIAN'",
        "QUANTITIES": "'4,13,20,30'", "APPARENT": "'AIRLESS'",
        "CSV_FORMAT": "'YES'", "EXTRA_PREC": "'YES'",
        "TIME_DIGITS": "'FRACSEC'", "ANG_FORMAT": "'DEG'",
        "RANGE_UNITS": "'AU'", "ELEV_CUT": "'-90'",
    }


def acquire():
    report = model_report()
    pending = {}
    for line, latitude, date, direction, minute in CASES:
        for service, endpoint, parameters in (
            ("horizons", HORIZONS, horizons_parameters(line, latitude, report)),
            ("usno", USNO, {"date": date, "coords": f"{latitude},0", "tz": "0", "dst": "false"}),
        ):
            url = endpoint + "?" + urllib.parse.urlencode(parameters)
            with urllib.request.urlopen(url, timeout=45) as response:
                data = response.read()
            value = json.loads(data)
            if "error" in value or (service == "horizons" and "$$SOE" not in value.get("result", "")):
                raise ValueError(f"invalid {service} response for line {line}: {value.get('error')}")
            name = f"{line}-{service}"
            pending[ARCHIVE / f"{name}.json"] = data
            pending[ARCHIVE / f"{name}.query.json"] = encoded({
                "endpoint": endpoint, "parameters": parameters, "url": url,
                "responseSHA256": sha(data),
                "acquiredUTC": dt.datetime.now(dt.timezone.utc).isoformat(),
            }).encode()
            print(f"acquired {name}", flush=True)
    # Publish pairs only after all acquisitions have succeeded.
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    for path, data in pending.items():
        path.write_bytes(data)


def read_pair(line, service, parameters):
    name = f"{line}-{service}"
    data = (ARCHIVE / f"{name}.json").read_bytes()
    recipe_path = ARCHIVE / f"{name}.query.json"
    recipe = json.loads(recipe_path.read_text())
    endpoint = HORIZONS if service == "horizons" else USNO
    if recipe["endpoint"] != endpoint or recipe["parameters"] != parameters or recipe["responseSHA256"] != sha(data):
        raise ValueError(f"detached response/query pair: {name}")
    if recipe["url"] != endpoint + "?" + urllib.parse.urlencode(parameters):
        raise ValueError(f"query URL mismatch: {name}")
    return json.loads(data), {"responseSHA256": sha(data), "querySHA256": sha(recipe_path.read_bytes())}


def parse_horizons(envelope, latitude, expected_epochs):
    result = envelope["result"]
    if envelope.get("signature", {}).get("source") != "NASA/JPL Horizons API":
        raise ValueError("unexpected Horizons source")
    for token in ("Sun (10)", "Earth (399)", "{source: DE441}", "ITRF93", "NO (AIRLESS)", "Date__(TT)__HR:MN"):
        if token not in result:
            raise ValueError(f"missing Horizons convention: {token}")
    geodetic = next(line for line in result.splitlines() if line.startswith("Center geodetic"))
    if f", {float(latitude):.1f}," not in geodetic:
        raise ValueError("wrong Horizons latitude")
    header = next(line for line in result.splitlines() if "Elevation_(a-app)" in line and "Date__" in line)
    columns = [c.strip() for c in next(csv.reader([header]))]
    index = {name: columns.index(name) for name in ("Date_________JDTT", "Elevation_(a-app)", "delta", "Ang-diam")}
    rows = []
    for line in result.split("$$SOE")[1].split("$$EOE")[0].strip().splitlines():
        cells = [c.strip() for c in next(csv.reader([line]))]
        row = {
            "ttDays": float(cells[index["Date_________JDTT"]]) - 2451545,
            "centerAltitudeDegrees": float(cells[index["Elevation_(a-app)"]]),
            "rangeAU": float(cells[index["delta"]]),
            "diameterArcseconds": float(cells[index["Ang-diam"]]),
        }
        if not all(math.isfinite(v) for v in row.values()) or row["rangeAU"] <= 0:
            raise ValueError("nonfinite or invalid Horizons row")
        # Adopt the production radius/refraction convention, not JPL RTS flags.
        row["matchedResidualDegrees"] = row["centerAltitudeDegrees"] + math.degrees(math.asin(695700 / (149597870.7 * row["rangeAU"]))) + 34 / 60
        row["fixed50ArcminResidualDegrees"] = row["centerAltitudeDegrees"] + 50 / 60
        diameter = 7200 * math.degrees(math.asin(695700 / (149597870.7 * row["rangeAU"])))
        if abs(diameter - row["diameterArcseconds"]) > 0.000501:
            raise ValueError("Horizons disk diameter does not match the adopted radius within printed rounding")
        rows.append(row)
    wanted = sorted(float(v) - 2451545 for v in expected_epochs.strip("'").split(","))
    if len(rows) != len(wanted) or any(abs(row["ttDays"] - tt) * 86400 > 0.001 for row, tt in zip(rows, wanted)):
        raise ValueError("Horizons epoch coverage mismatch")
    return rows, {k: next(line.strip() for line in result.splitlines() if line.startswith(k)) for k in ("Target body name:", "Center body name:", "Center geodetic", "Center pole/equ", "EOP file", "EOP coverage", "Target radii")}


def interpolate_root(rows, key):
    # Only regular 30-second samples; exact model event rows can nearly coincide.
    grid = [row for i, row in enumerate(rows) if i == 0 or abs((row["ttDays"] - rows[0]["ttDays"]) * 2880 - round((row["ttDays"] - rows[0]["ttDays"]) * 2880)) < 0.0001]
    crossings = [i for i in range(len(grid) - 1) if grid[i][key] * grid[i + 1][key] <= 0]
    if len(crossings) != 1:
        raise ValueError("reference must bracket exactly one horizon crossing")
    i = crossings[0]
    left, right = grid[i:i+2]
    base = left["ttDays"]
    span = (right["ttDays"] - base) * 86400
    linear = -left[key] * span / (right[key] - left[key])
    nearby = grid[max(0, i-1):max(0, i-1)+3]
    nodes = [((row["ttDays"] - base) * 86400, row[key]) for row in nearby]
    def value(x):
        return sum(y * math.prod((x - xj) / (xi - xj) for j, (xj, _) in enumerate(nodes) if j != n) for n, (xi, y) in enumerate(nodes))
    lo, hi = 0.0, span
    increasing = right[key] > left[key]
    for _ in range(45):
        mid = (lo + hi) / 2
        if (value(mid) < 0) == increasing:
            lo = mid
        else:
            hi = mid
    seconds = (lo + hi) / 2
    return {"ttDays": base + seconds / 86400, "linearQuadraticDifferenceSeconds": seconds - linear, "altitudeSlopeDegreesPerSecond": (right[key] - left[key]) / span}


def build_report():
    model = model_report()
    records = []
    inputs = {DIAGNOSIS.relative_to(ROOT).as_posix(): sha(DIAGNOSIS.read_bytes())}
    for line, latitude, date, direction, minute in CASES:
        params = horizons_parameters(line, latitude, model)
        jpl, hashes = read_pair(line, "horizons", params)
        inputs[f"{line}-horizons"] = hashes
        rows, metadata = parse_horizons(jpl, latitude, params["TLIST"])
        usno, hashes = read_pair(line, "usno", {"date": date, "coords": f"{latitude},0", "tz": "0", "dst": "false"})
        inputs[f"{line}-usno"] = hashes
        data = usno["properties"]["data"]
        if usno["geometry"]["coordinates"] != [0, latitude] or data["tz"] != 0 or data["isdst"] or (data["year"], data["month"], data["day"]) != tuple(map(int, date.split("-"))):
            raise ValueError("USNO returned wrong location/date/time convention")
        live_events = [event["time"] for event in data["sundata"] if event["phen"] == {"R": "Rise", "S": "Set"}[direction]]
        if live_events != [minute]:
            raise ValueError(f"USNO no longer repeats the archived event: {line}")
        matched = interpolate_root(rows, "matchedResidualDegrees")
        fixed = interpolate_root(rows, "fixed50ArcminResidualDegrees")
        records.append({
            "sourceLine": line, "latitudeDegrees": latitude, "date": date,
            "direction": direction, "archivedMinuteUT1": minute,
            "liveUSNOMinuteUT1": live_events[0], "liveUSNOAPIVersion": usno["apiversion"],
            "horizonsMetadata": metadata, "horizonsAPISignature": jpl["signature"], "matchedReference": matched,
            "fixed50ArcminConventionControl": fixed,
            "fixedVersusMatchedSeconds": (fixed["ttDays"] - matched["ttDays"]) * 86400,
            "models": {name: {
                "eventTTDays": events(model, name)[line]["eventTT"],
                "signedSecondsFromMatchedReference": (events(model, name)[line]["eventTT"] - matched["ttDays"]) * 86400,
                "referenceAltitudeResidualAtModelEventDegrees": min(rows, key=lambda row: abs(row["ttDays"] - events(model, name)[line]["eventTT"]))["matchedResidualDegrees"],
            } for name in ("current", "pinned")},
        })
    return {
        "schemaVersion": 1, "inputs": inputs,
        "claim": "Four finite independent horizon diagnostics, not a production model ranking or acceptance threshold.",
        "referenceConvention": "JPL DE441 airless apparent topocentric Sun center; exact WGS84/ITRF93 pole at zero height; production-compatible variable semidiameter asin(695700 km/range) plus fixed 34 arcmin refraction; explicit TT epochs.",
        "remainingDifferences": [
            "Horizons historical EOP/polar motion and corrected IAU76/80 orientation differ from the engine's idealized true-equator pole and orientation model.",
            "JPL includes gravitational light deflection; the production-equator path is not identical in all correction details.",
            "USNO minute output is UT1, not Horizons UTC. Generic fixed-50-arcmin documentation is a convention control, not a verified literal oneday API algorithm.",
            "Interpolation/output precision diagnostics do not bound physical atmospheric or model uncertainty.",
        ],
        "events": records,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("acquire", "report", "check"))
    args = parser.parse_args()
    if args.action == "acquire":
        acquire()
        return
    report = encoded(build_report())
    if args.action == "check":
        if REPORT.read_text() != report:
            raise ValueError("stale reference report; regenerate with report")
        print("independent polar reference archive and report verified")
    else:
        REPORT.write_text(report)
        print(f"wrote {REPORT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
