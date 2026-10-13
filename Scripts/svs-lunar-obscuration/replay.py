#!/usr/bin/env python3
"""Replay the bounded 2026 SVS lunar-obscuration source comparison."""

import argparse
import csv
import hashlib
import html
import json
import math
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RECEIPTS = HERE / "source-receipts.json"
RESULTS = HERE / "results.json"
TARGET_JD_TT = "2461280.676452763"
AU_KILOMETERS = 149_597_870.700
EARTH_RADIUS_KILOMETERS = 6_378.1366
MOON_RADIUS_KILOMETERS = 1_737.4
SUN_RADIUS_KILOMETERS = 695_700.0
DANJON_PARALLAX_FACTOR = 1.01
PRINTED_OBSCURATION = 0.963
PRINT_INTERVAL = (0.9625, 0.9635)


class EvidenceError(ValueError):
    """The pinned evidence or its declared semantics changed."""


def file_sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path):
    return json.loads(path.read_text())


def repository_path(value, label):
    relative = Path(value)
    if relative.is_absolute():
        raise EvidenceError(f"{label} path must be repository-relative")
    resolved = (ROOT / relative).resolve()
    try:
        resolved.relative_to(ROOT.resolve())
    except ValueError as error:
        raise EvidenceError(f"{label} path escapes the repository") from error
    return resolved


def snapshot_path(value, label):
    resolved = repository_path(value, label)
    try:
        resolved.relative_to((HERE / "sources").resolve())
    except ValueError as error:
        raise EvidenceError(f"{label} path is outside the issue-owned source snapshots") from error
    return resolved


def verify_file(path, expected_sha256, label):
    if not path.is_file():
        raise EvidenceError(f"{label} is missing: {path.relative_to(ROOT)}")
    actual = file_sha256(path)
    if actual != expected_sha256:
        raise EvidenceError(f"{label} SHA-256 changed: expected {expected_sha256}, found {actual}")


def verify_receipts(receipts):
    if receipts.get("schemaVersion") != 1:
        raise EvidenceError("unsupported source-receipt schema")
    for label, source in receipts["sources"].items():
        path = snapshot_path(source["archivePath"], label)
        verify_file(path, source["sha256"], label)
        if "queryPath" in source:
            verify_file(snapshot_path(source["queryPath"], f"{label} query"), source["querySHA256"], f"{label} query")
        text = path.read_text()
        for required in source.get("requiredText", []):
            if required not in text:
                raise EvidenceError(f"{label} no longer contains required source text: {required}")
    for label, artifact in receipts["supportingArtifacts"].items():
        verify_file(snapshot_path(artifact["path"], label), artifact["sha256"], label)


def horizons_row(source):
    response = load_json(snapshot_path(source["archivePath"], "Horizons response"))
    query = load_json(snapshot_path(source["queryPath"], "Horizons query"))
    if response.get("signature", {}).get("source") != "NASA/JPL Horizons API":
        raise EvidenceError("Horizons response signature changed")
    if query.get("responseSHA256") != source["sha256"]:
        raise EvidenceError("Horizons query does not bind its response")
    if query.get("parameters", {}).get("TIME_TYPE") != "'TT'":
        raise EvidenceError("Horizons query time scale is not TT")
    ephemeris = re.search(r"Center body name: Earth.*?\{source: ([^}]+)\}", response["result"])
    if ephemeris is None:
        raise EvidenceError("Horizons center ephemeris is missing")
    rows = list(csv.reader(response["result"].split("$$SOE\n", 1)[1].split("$$EOE", 1)[0].splitlines()))
    matches = [row for row in rows if row[0].strip() == TARGET_JD_TT]
    if len(matches) != 1:
        raise EvidenceError(f"expected one Horizons row at JD TT {TARGET_JD_TT}")
    row = matches[0]
    return {
        "declinationDegrees": float(row[11]),
        "distanceAU": float(row[7]),
        "ephemeris": ephemeris.group(1),
        "jdTT": row[0].strip(),
        "raDegrees": float(row[10]),
    }


def unit_vector(ra_degrees, declination_degrees):
    right_ascension = math.radians(ra_degrees)
    declination = math.radians(declination_degrees)
    return (
        math.cos(declination) * math.cos(right_ascension),
        math.cos(declination) * math.sin(right_ascension),
        math.sin(declination),
    )


def circle_overlap_fraction(first_radius, second_radius, separation):
    if separation >= first_radius + second_radius:
        return 0.0
    if separation <= abs(first_radius - second_radius):
        ratio = second_radius / first_radius
        return min(1.0, ratio * ratio)
    first_angle = math.acos(
        (separation * separation + first_radius * first_radius - second_radius * second_radius)
        / (2 * separation * first_radius)
    )
    second_angle = math.acos(
        (separation * separation + second_radius * second_radius - first_radius * first_radius)
        / (2 * separation * second_radius)
    )
    product = (
        (-separation + first_radius + second_radius)
        * (separation + first_radius - second_radius)
        * (separation - first_radius + second_radius)
        * (separation + first_radius + second_radius)
    )
    area = first_radius * first_radius * first_angle + second_radius * second_radius * second_angle - 0.5 * math.sqrt(product)
    return area / (math.pi * first_radius * first_radius)


def replay_overlap(sun, moon):
    sun_vector = unit_vector(sun["raDegrees"], sun["declinationDegrees"])
    moon_vector = unit_vector(moon["raDegrees"], moon["declinationDegrees"])
    shadow_vector = tuple(-component for component in sun_vector)
    dot = sum(a * b for a, b in zip(shadow_vector, moon_vector))
    cross = (
        shadow_vector[1] * moon_vector[2] - shadow_vector[2] * moon_vector[1],
        shadow_vector[2] * moon_vector[0] - shadow_vector[0] * moon_vector[2],
        shadow_vector[0] * moon_vector[1] - shadow_vector[1] * moon_vector[0],
    )
    separation_angle = math.atan2(math.sqrt(sum(component * component for component in cross)), dot)
    moon_distance = moon["distanceAU"] * AU_KILOMETERS
    sun_distance = sun["distanceAU"] * AU_KILOMETERS
    moon_radius = moon_distance * math.tan(math.asin(MOON_RADIUS_KILOMETERS / moon_distance))
    umbra_angle = (
        DANJON_PARALLAX_FACTOR * math.asin(EARTH_RADIUS_KILOMETERS / moon_distance)
        - math.asin(SUN_RADIUS_KILOMETERS / sun_distance)
        + math.asin(EARTH_RADIUS_KILOMETERS / sun_distance)
    )
    umbra_radius = moon_distance * math.tan(umbra_angle)
    axis_distance = moon_distance * math.tan(separation_angle)
    return {
        "axisDistanceKilometers": axis_distance,
        "moonRadiusKilometers": moon_radius,
        "obscuration": circle_overlap_fraction(moon_radius, umbra_radius, axis_distance),
        "separationArcseconds": math.degrees(separation_angle) * 3_600,
        "umbraRadiusKilometers": umbra_radius,
    }


def in_print_interval(value):
    return PRINT_INTERVAL[0] <= value <= PRINT_INTERVAL[1]


def catalog_facts(receipts):
    text = snapshot_path(receipts["sources"]["catalog"]["archivePath"], "catalog").read_text()
    line = next(line for line in text.splitlines() if "2026 Aug 28  04:14:04" in line)
    fields = html.unescape(re.sub(r"<[^>]+>", " ", line)).split()
    if len(fields) != 18 or fields[1:4] != ["2026", "Aug", "28"]:
        raise EvidenceError("2026 catalog row structure changed")
    return {"greatestEclipseUT": fields[4], "umbralMagnitude": float(fields[12])}


def native_result(receipts):
    captures = load_json(snapshot_path(receipts["supportingArtifacts"]["nativeCapture"]["path"], "native capture"))
    values = []
    for configuration in ("debug", "release"):
        matches = [
            row
            for row in captures[configuration]["obscurations"]
            if row["sourceTimeSearchSeed"].startswith("2026-08-28")
        ]
        if len(matches) != 1:
            raise EvidenceError(f"expected one 2026 native {configuration} capture")
        values.append(matches[0]["obscuration"])
    if values[0] != values[1]:
        raise EvidenceError("native Debug and Release obscurations differ")
    return values[0]


def build_results(receipts):
    sun = horizons_row(receipts["sources"]["horizonsSun"])
    moon = horizons_row(receipts["sources"]["horizonsMoon"])
    replay = replay_overlap(sun, moon)
    independent = load_json(snapshot_path(receipts["supportingArtifacts"]["independentOverlap"]["path"], "independent overlap"))["lunarOverlap"]["expected"]
    independent_obscuration = float(independent["obscuration"])
    if abs(replay["obscuration"] - independent_obscuration) > 2e-14:
        raise EvidenceError("standard-library replay differs from the archived 80-digit overlap")
    catalog = catalog_facts(receipts)
    native = native_result(receipts)
    negative_controls = {
        "catalogMagnitudeIsSVSArea": catalog["umbralMagnitude"] == PRINTED_OBSCURATION,
        "catalogTimeEqualsSVSPrintedMinute": catalog["greatestEclipseUT"] == "04:13:00",
        "horizonsDE441ReplayMatchesSVSPrintInterval": in_print_interval(replay["obscuration"]),
        "horizonsEphemerisEqualsSVSNamedEphemeris": sun["ephemeris"] == "DE421" and moon["ephemeris"] == "DE421",
        "nativeCaptureMatchesSVSPrintInterval": in_print_interval(native),
    }
    if any(negative_controls.values()):
        raise EvidenceError("a source-substitution negative control unexpectedly passed")
    return {
        "comparison": {
            "conditionalNearestPrintInterval": list(PRINT_INTERVAL),
            "horizonsDE441DanjonReplay": replay,
            "nativeCapturedObscuration": native,
            "svsPrintedObscuration": PRINTED_OBSCURATION,
        },
        "conventions": {
            "catalog": {
                "ephemerides": "VSOP87 Sun and ELP-2000/82 Moon",
                "greatestEclipseUT": catalog["greatestEclipseUT"],
                "measure": "umbral magnitude, a diameter fraction",
                "shadow": "Danjon enlargement",
                "value": catalog["umbralMagnitude"],
            },
            "horizonsReplay": {
                "ephemeris": sun["ephemeris"],
                "epoch": f"JD TT {TARGET_JD_TT}",
                "measure": "Moon-disc area inside a circular Danjon umbra",
                "positions": "geocentric airless apparent directions in ICRF",
            },
            "svs": {
                "datasetsNamed": ["DE421", "LOLA", "5MCLE"],
                "greatestEclipseUT": "04:13 (printed minute)",
                "measure": "Moon-disc area inside the umbra",
            },
        },
        "negativeControls": negative_controls,
        "outcome": {
            "exactSVSConventionReproduced": False,
            "missingSourceFields": [
                "DE421 realization and state vectors used by the visualization",
                "full-precision peak epoch and time scale",
                "Sun, Earth, Moon, and umbra radii",
                "LOLA limb or topography treatment in the 96.3% calculation",
                "projection and overlap algorithm",
                "full-precision obscuration and rounding rule",
            ],
            "productionDefectEstablished": False,
        },
        "schemaVersion": 1,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="verify sources and the committed result")
    mode.add_argument("--write", action="store_true", help="regenerate the deterministic result")
    args = parser.parse_args()
    receipts = load_json(RECEIPTS)
    verify_receipts(receipts)
    result_text = json.dumps(build_results(receipts), indent=2, sort_keys=True) + "\n"
    if args.check:
        if not RESULTS.is_file() or RESULTS.read_text() != result_text:
            raise SystemExit("replay result differs; run with --write and review the source/convention change")
        print("Pinned SVS, catalog, Horizons, and repository comparisons verified; exact SVS convention remains unavailable")
    else:
        RESULTS.write_text(result_text)
        print(RESULTS.relative_to(ROOT))


if __name__ == "__main__":
    main()
