#!/usr/bin/env python3
"""Replay the lunar-frame preflight from pinned source snapshots."""

import argparse
import datetime as dt
import hashlib
import html.parser
import json
import math
import os
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCES = ROOT / "sources"
BASE_REVISION = "3c31e2d56eb4e887554ea185f5f75bdb78b3a674"
SOURCE_TREE = "b091889be7c0a2aad04819086367350836f75acf"
CAPTURE_TOOLCHAIN = "Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1) Target: arm64-apple-macosx27.0.0"
CAPTURE_PATH = "base-libration.json"
CAPTURE_PROGRAM_PATH = "capture.swift"
RECEIPTS_PATH = ROOT / "source-receipts.json"
REPORT_PATH = ROOT / "report.json"
TABLE_NAMES = tuple("mooninfo_{}.txt".format(year) for year in range(2020, 2023))
PAGE_IDS = (4768, 4874, 4955)
SOURCE_PATHS = {
    "sources/astronomy-engine-license.txt",
    "sources/moon_de440_250416.tf",
    "sources/moon_pa_de440_200625.cmt",
    *("sources/{}".format(name) for name in TABLE_NAMES),
    *("sources/nasa-svs-{}.html".format(identifier) for identifier in PAGE_IDS),
}
ROW_LAYOUT = ["universalTime", "terrestrialTime", "longitudeDegrees", "latitudeDegrees"]
CAPTURE_COMMAND = ["swift build -Xswiftc -enable-testing", "swiftc -I .build/out/Products/Debug Scripts/lunar-frame-preflight/capture.swift .build/out/Products/Debug/AstronomyKit.o .build/out/Products/Debug/CLibAstronomy.o -o /tmp/lunar-frame-capture", "/tmp/lunar-frame-capture Scripts/lunar-frame-preflight/sources Scripts/lunar-frame-preflight/base-libration.json {} {} \"{}\"".format(BASE_REVISION, SOURCE_TREE, CAPTURE_TOOLCHAIN)]
MONTHS = {name: index + 1 for index, name in enumerate(("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"))}
J2000_UTC = dt.datetime(2000, 1, 1, 12, tzinfo=dt.timezone.utc)


class ReplayError(ValueError):
    pass


class TextExtractor(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contained_path(relative):
    if not isinstance(relative, str) or Path(relative).is_absolute() or ".." in Path(relative).parts or Path(relative).as_posix() != relative:
        raise ReplayError("receipt path is not a canonical relative path: {!r}".format(relative))
    resolved = (ROOT / relative).resolve()
    if os.path.commonpath((str(ROOT), str(resolved))) != str(ROOT):
        raise ReplayError("receipt path escapes the preflight directory: {}".format(relative))
    if resolved.is_symlink() or not resolved.is_file():
        raise ReplayError("receipt path is not a regular file: {}".format(relative))
    return resolved


def read_receipts(data=None):
    receipt = json.loads(RECEIPTS_PATH.read_text()) if data is None else data
    if set(receipt) != {"schemaVersion", "baseRevision", "capture", "sources"} or receipt["schemaVersion"] != 1 or receipt["baseRevision"] != BASE_REVISION:
        raise ReplayError("receipt schema or base revision differs")
    sources = receipt["sources"]
    if not isinstance(sources, list) or {entry.get("path") for entry in sources if isinstance(entry, dict)} != SOURCE_PATHS or len(sources) != len(SOURCE_PATHS):
        raise ReplayError("source receipt inventory differs")
    for entry in sources:
        if set(entry) != {"path", "sha256", "bytes", "origin"}:
            raise ReplayError("source receipt fields differ")
        path = contained_path(entry["path"])
        if not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"]) or digest(path) != entry["sha256"] or path.stat().st_size != entry["bytes"]:
            raise ReplayError("source receipt content differs: {}".format(entry["path"]))
        origin = entry["origin"]
        if not isinstance(origin, dict) or origin.get("kind") not in {"exactBaseCopy", "https"}:
            raise ReplayError("source origin differs: {}".format(entry["path"]))
        if origin["kind"] == "exactBaseCopy":
            if set(origin) != {"kind", "baseRevision", "basePath", "publisherURL"} or origin.get("baseRevision") != BASE_REVISION or not origin.get("basePath") or not origin.get("publisherURL", "").startswith("https://"):
                raise ReplayError("base-copy origin is incomplete: {}".format(entry["path"]))
        else:
            if set(origin) not in ({"kind", "url", "retrievedAt", "contentLength"}, {"kind", "url", "retrievedAt", "contentLength", "lastModified"}) or not origin.get("url", "").startswith("https://") or not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", origin.get("retrievedAt", "")) or origin.get("contentLength") != entry["bytes"]:
                raise ReplayError("HTTPS origin is incomplete: {}".format(entry["path"]))
            if "lastModified" in origin and not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", origin["lastModified"]):
                raise ReplayError("HTTPS last-modified time differs: {}".format(entry["path"]))
    capture = receipt["capture"]
    if set(capture) != {"path", "sha256", "bytes", "revision", "astronomyKitSourceTree", "program", "command"}:
        raise ReplayError("capture receipt fields differ")
    path = contained_path(capture["path"])
    if capture["path"] != CAPTURE_PATH or capture["revision"] != BASE_REVISION or capture["astronomyKitSourceTree"] != SOURCE_TREE or digest(path) != capture["sha256"] or path.stat().st_size != capture["bytes"]:
        raise ReplayError("capture receipt differs")
    program = capture["program"]
    if set(program) != {"path", "sha256"} or program["path"] != CAPTURE_PROGRAM_PATH or digest(contained_path(program["path"])) != program["sha256"]:
        raise ReplayError("capture program receipt differs")
    if capture["command"] != CAPTURE_COMMAND:
        raise ReplayError("capture command differs")
    return receipt


def page_text(identifier):
    parser = TextExtractor()
    parser.feed((SOURCES / "nasa-svs-{}.html".format(identifier)).read_text())
    return " ".join(" ".join(parser.parts).split())


def source_contract():
    pages = {}
    for identifier, year in zip(PAGE_IDS, range(2020, 2023)):
        text = page_text(identifier)
        required = [
            "ID: {}".format(identifier),
            "Time (UTC)",
            "Sub-Earth Longitude, Latitude",
            "geocentric phase, libration, position angle of the axis, and apparent diameter",
            "throughout the year {}, at hourly intervals".format(year),
            "The sub-Earth point is also the apparent center of the Moon's disk",
            "DE421 (JPL DE421)",
            "we do not store any further details",
        ]
        missing = [phrase for phrase in required if phrase not in text]
        if missing:
            raise ReplayError("SVS {} source contract is missing {}".format(identifier, missing))
        pages[str(identifier)] = {"year": year, "timeLabel": "UTC", "observer": "geocentric", "quantity": "sub-Earth longitude and latitude", "modelNamed": "JPL DE421", "bodyFixedFrameNamed": False, "lightTimeRecipeNamed": False}
    comment = " ".join((SOURCES / "moon_pa_de440_200625.cmt").read_text().split())
    for phrase in ("moon_pa_de440_200625.bpc", "orientation of the lunar Principal Axes (PA) reference frame defined by DE440, relative to the ICRF", "variant of the Mean Earth/Polar Axis (ME) reference frame", "1549 DEC 31 00:00:00.000", "2650 JAN 25 00:00:00.000"):
        if phrase not in comment:
            raise ReplayError("NAIF PCK comment contract is missing {!r}".format(phrase))
    frame = (SOURCES / "moon_de440_250416.tf").read_text()
    normalized_frame = " ".join(frame.split())
    for phrase in ("MOON_PA_DE440 ICRF/J2000 PCK 31008", "MOON_ME_DE440_ME421 MOON_PA_DE440 FIXED 31009", "J2000 pole offset magnitude is about 18 milliarcseconds", "these data are provided for backward compatibility"):
        if phrase not in normalized_frame:
            raise ReplayError("NAIF frame contract is missing {!r}".format(phrase))
    angle_match = re.search(r"TKFRAME_31009_ANGLES\s*=\s*\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\)", frame)
    axes_match = re.search(r"TKFRAME_31009_AXES\s*=\s*\(\s*(\d),\s*(\d),\s*(\d)\s*\)", frame)
    unit_match = re.search(r"TKFRAME_31009_UNITS\s*=\s*'([^']+)'", frame)
    if not angle_match or not axes_match or not unit_match:
        raise ReplayError("NAIF fixed-frame rotation is unreadable")
    angles = [float(value) for value in angle_match.groups()]
    axes = [int(value) for value in axes_match.groups()]
    if angles != [67.8526, 78.6944, 0.2785] or axes != [3, 2, 1] or unit_match.group(1) != "ARCSECONDS":
        raise ReplayError("NAIF fixed-frame rotation differs")
    return {"svs": pages, "naif": {"pckCoverageTDB": ["1549-12-31T00:00:00", "2650-01-25T00:00:00"], "dynamicFrame": "MOON_PA_DE440 relative to ICRF", "fixedFrame": "MOON_ME_DE440_ME421 relative to MOON_PA_DE440", "anglesArcseconds": angles, "axes": axes}}


def parse_tables():
    rows = []
    coverage = {}
    for name, year in zip(TABLE_NAMES, range(2020, 2023)):
        lines = (SOURCES / name).read_text().splitlines()
        if not lines or lines[0].split() != ["Date", "Time", "Phase", "Age", "Diam", "Dist", "RA", "Dec", "Slon", "Slat", "Elon", "Elat", "AxisA"]:
            raise ReplayError("{} header differs".format(name))
        year_rows = []
        for line_number, line in enumerate(lines[1:], 2):
            fields = line.split()
            if len(fields) != 16 or fields[4] != "UT":
                raise ReplayError("{}:{} row differs".format(name, line_number))
            stamp = dt.datetime(int(fields[2]), MONTHS[fields[1]], int(fields[0]), *map(int, fields[3].split(":")), tzinfo=dt.timezone.utc)
            row = {"source": name, "sourceLine": line_number, "stamp": stamp, "universalTime": (stamp - J2000_UTC).total_seconds() / 86400, "longitudeDegrees": float(fields[13]), "latitudeDegrees": float(fields[14])}
            year_rows.append(row)
            rows.append(row)
        expected = 8785 if year == 2020 else 8760
        expected_end = dt.datetime(2021, 1, 1, tzinfo=dt.timezone.utc) if year == 2020 else dt.datetime(year, 12, 31, 23, tzinfo=dt.timezone.utc)
        if len(year_rows) != expected or year_rows[0]["stamp"] != dt.datetime(year, 1, 1, tzinfo=dt.timezone.utc) or year_rows[-1]["stamp"] != expected_end:
            raise ReplayError("{} coverage differs".format(name))
        if any((right["stamp"] - left["stamp"]).total_seconds() != 3600 for left, right in zip(year_rows, year_rows[1:])):
            raise ReplayError("{} cadence differs".format(name))
        coverage[str(year)] = {"rows": len(year_rows), "startUTC": year_rows[0]["stamp"].isoformat().replace("+00:00", "Z"), "endUTC": year_rows[-1]["stamp"].isoformat().replace("+00:00", "Z"), "stepSeconds": 3600}
    if len(rows) != 26305:
        raise ReplayError("SVS row count differs")
    return rows, coverage


def paired_rows():
    source_rows, coverage = parse_tables()
    capture = json.loads((ROOT / CAPTURE_PATH).read_text())
    if set(capture) != {"schemaVersion", "captureRevision", "astronomyKitSourceTree", "toolchain", "sourceOrder", "rowLayout", "rows"} or capture["schemaVersion"] != 1 or capture["captureRevision"] != BASE_REVISION or capture["astronomyKitSourceTree"] != SOURCE_TREE or capture["toolchain"] != CAPTURE_TOOLCHAIN or capture["sourceOrder"] != list(TABLE_NAMES) or capture["rowLayout"] != ROW_LAYOUT:
        raise ReplayError("capture schema or provenance differs")
    if len(capture["rows"]) != len(source_rows):
        raise ReplayError("capture row count differs")
    pairs = []
    for source, values in zip(source_rows, capture["rows"]):
        if not isinstance(values, list) or len(values) != 4 or any(not isinstance(value, (float, int)) or not math.isfinite(value) for value in values):
            raise ReplayError("capture row differs")
        ut, tt, longitude, latitude = values
        if abs(ut - source["universalTime"]) > 1e-12 or not 0 < tt - ut < 0.002:
            raise ReplayError("capture clock differs at {}:{}".format(source["source"], source["sourceLine"]))
        pairs.append({**source, "modelLongitudeDegrees": longitude, "modelLatitudeDegrees": latitude, "terrestrialTime": tt})
    return pairs, coverage, capture["toolchain"]


def rotation(axis, angle):
    cosine, sine = math.cos(angle), math.sin(angle)
    if axis == 1:
        return ((1.0, 0.0, 0.0), (0.0, cosine, -sine), (0.0, sine, cosine))
    if axis == 2:
        return ((cosine, 0.0, sine), (0.0, 1.0, 0.0), (-sine, 0.0, cosine))
    if axis == 3:
        return ((cosine, -sine, 0.0), (sine, cosine, 0.0), (0.0, 0.0, 1.0))
    raise ReplayError("rotation axis differs")


def matrix_product(left, right):
    return tuple(tuple(sum(left[row][k] * right[k][column] for k in range(3)) for column in range(3)) for row in range(3))


def transpose(matrix):
    return tuple(zip(*matrix))


def pa_to_me_matrix(angles, axes):
    matrix = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    for axis, angle in reversed(list(zip(axes, angles))):
        matrix = matrix_product(matrix, rotation(axis, math.radians(angle / 3600)))
    return matrix


def transformed(longitude, latitude, matrix):
    longitude, latitude = math.radians(longitude), math.radians(latitude)
    vector = (math.cos(latitude) * math.cos(longitude), math.cos(latitude) * math.sin(longitude), math.sin(latitude))
    rotated = tuple(sum(matrix[row][column] * vector[column] for column in range(3)) for row in range(3))
    return math.degrees(math.atan2(rotated[1], rotated[0])), math.degrees(math.atan2(rotated[2], math.hypot(rotated[0], rotated[1])))


def longitude_offset(left, right):
    return (left - right + 180) % 360 - 180


def summarize(values, rows):
    worst_index = max(range(len(values)), key=lambda index: abs(values[index]))
    worst = rows[worst_index]
    return {"meanSigned": sum(values) / len(values), "rms": math.sqrt(sum(value * value for value in values) / len(values)), "maxAbsolute": abs(values[worst_index]), "worst": {"source": worst["source"], "sourceLine": worst["sourceLine"], "stampUTC": worst["stamp"].isoformat().replace("+00:00", "Z"), "signed": values[worst_index]}}


def compare(rows, matrix=None):
    latitude, longitude, angular = [], [], []
    for row in rows:
        model_longitude, model_latitude = row["modelLongitudeDegrees"], row["modelLatitudeDegrees"]
        if matrix is not None:
            model_longitude, model_latitude = transformed(model_longitude, model_latitude, matrix)
        latitude.append(60 * (model_latitude - row["latitudeDegrees"]))
        longitude.append(60 * longitude_offset(model_longitude, row["longitudeDegrees"]))
        left = tuple(map(math.radians, (model_longitude, model_latitude)))
        right = tuple(map(math.radians, (row["longitudeDegrees"], row["latitudeDegrees"])))
        left_vector = (math.cos(left[1]) * math.cos(left[0]), math.cos(left[1]) * math.sin(left[0]), math.sin(left[1]))
        right_vector = (math.cos(right[1]) * math.cos(right[0]), math.cos(right[1]) * math.sin(right[0]), math.sin(right[1]))
        cross = (left_vector[1] * right_vector[2] - left_vector[2] * right_vector[1], left_vector[2] * right_vector[0] - left_vector[0] * right_vector[2], left_vector[0] * right_vector[1] - left_vector[1] * right_vector[0])
        angular.append(60 * math.degrees(math.atan2(math.sqrt(sum(value * value for value in cross)), sum(a * b for a, b in zip(left_vector, right_vector)))))
    return {"latitudeArcminutes": summarize(latitude, rows), "longitudeArcminutes": summarize(longitude, rows), "angularSeparationArcminutes": summarize(angular, rows)}


def shifted_control(rows):
    shifted = []
    for source, model in zip(rows[:-1], rows[1:]):
        shifted.append({**source, "modelLongitudeDegrees": model["modelLongitudeDegrees"], "modelLatitudeDegrees": model["modelLatitudeDegrees"]})
    return compare(shifted)


def swapped_control(rows):
    return compare([{**row, "modelLongitudeDegrees": row["modelLatitudeDegrees"], "modelLatitudeDegrees": row["modelLongitudeDegrees"]} for row in rows])


def analyze():
    read_receipts()
    contract = source_contract()
    rows, coverage, toolchain = paired_rows()
    matrix = pa_to_me_matrix(contract["naif"]["anglesArcseconds"], contract["naif"]["axes"])
    inverse = transpose(matrix)
    identity = compare(rows)
    pa_to_me = compare(rows, matrix)
    me_to_pa = compare(rows, inverse)
    latitude_reduction = 1 - pa_to_me["latitudeArcminutes"]["rms"] / identity["latitudeArcminutes"]["rms"]
    longitude_gate_ratio = pa_to_me["longitudeArcminutes"]["maxAbsolute"] / 0.1304
    return {"schemaVersion": 1, "baseRevision": BASE_REVISION, "captureToolchain": toolchain, "coverage": {"totalRows": len(rows), "tables": coverage, "svsClock": "UTC labels replayed as UT coordinates; exact-base capture converts UT to TT with Espenak-Meeus Delta T", "naifClock": "DE440 binary PCK coverage is stated in ET/TDB", "observer": "SVS states geocentric and calls the sub-Earth point the apparent disc center", "lightTime": "SVS does not publish its light-time or aberration recipe; the fixed PA/ME rotation tested here is epoch-independent"}, "sourceContract": contract, "frameMatrixPAtoME": [list(row) for row in matrix], "comparisons": {"identity": identity, "interpretBaseAsPAThenConvertToME": pa_to_me, "interpretBaseAsMEThenConvertToPA": me_to_pa}, "negativeControls": {"oneHourShift": shifted_control(rows), "longitudeLatitudeSwap": swapped_control(rows), "reverseFrameDirection": me_to_pa}, "finding": {"identityLatitudeMeanSignedArcminutes": identity["latitudeArcminutes"]["meanSigned"], "identityLatitudeMaxArcminutes": identity["latitudeArcminutes"]["maxAbsolute"], "identityLongitudeMaxArcminutes": identity["longitudeArcminutes"]["maxAbsolute"], "paToMeLatitudeRMSReductionFraction": latitude_reduction, "paToMeLatitudeMaxArcminutes": pa_to_me["latitudeArcminutes"]["maxAbsolute"], "paToMeLongitudeMaxArcminutes": pa_to_me["longitudeArcminutes"]["maxAbsolute"], "paToMeLongitudeGateRatio": longitude_gate_ratio, "supportedConclusion": "The fixed DE440 PA-to-ME rotation removes most of the steady latitude bias but creates a longitude error above the existing longitude gate, so a whole-frame convention swap does not explain the SVS comparison.", "unresolved": ["SVS does not name its lunar body-fixed frame or orientation-kernel version.", "SVS names DE421 but does not publish the state, light-time, aberration, emission-time, or reception-time recipe behind the sub-Earth coordinates.", "This preflight does not evaluate the DE440 binary PCK orientation or choose a runtime blend and transition."]}}


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    arguments = parser.parse_args()
    result = encoded(analyze())
    if arguments.write:
        temporary = REPORT_PATH.with_suffix(".json.tmp")
        temporary.write_bytes(result)
        temporary.replace(REPORT_PATH)
    elif not REPORT_PATH.exists() or REPORT_PATH.read_bytes() != result:
        raise ReplayError("report.json differs; run replay.py --write and review the result")
    print("lunar frame preflight: {} rows verified".format(json.loads(result)["coverage"]["totalRows"]))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ReplayError, json.JSONDecodeError) as error:
        print("lunar frame preflight: {}".format(error), file=sys.stderr)
        raise SystemExit(1)
