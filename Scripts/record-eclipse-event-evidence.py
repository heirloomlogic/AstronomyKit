#!/usr/bin/env python3
"""Record and verify native lunar-eclipse observations and source bindings."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Scripts/eclipse-data"
CAPTURES = DATA / "native-captures.json"
OUTPUT = DATA / "native-evidence.json"


def source_hashes(capture_bytes=None):
    paths = list((ROOT / "Sources/AstronomyKit/Engine").rglob("*.swift"))
    paths += [
        ROOT / "Sources/AstronomyKit/AstronomyError.swift",
        ROOT / "Sources/AstronomyKit/CelestialBody.swift",
        ROOT / "Sources/AstronomyKit/Time.swift",
        ROOT / "Tests/AstronomyKitTests/Engine/Eclipses/EngineEclipseEventTests.swift",
        ROOT / "Tests/AstronomyKitTests/IndependentReferenceFixtures.swift",
        ROOT / "Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json",
        ROOT / "Scripts/reference-data/build-fixtures.py",
        ROOT / "Scripts/reference-data/sources/lunar_1701.html",
        ROOT / "Scripts/reference-data/sources/lunar_1901.html",
        ROOT / "Scripts/reference-data/sources/lunar_2001.html",
        ROOT / "Scripts/reference-data/sources/nasa-lunar-2001-2100.html",
        ROOT / "Scripts/reference-data/sources/nasa-oh2001.html",
        ROOT / "Scripts/reference-data/sources/nasa-shadow-enlargement.html",
        ROOT / "Scripts/reference-data/sources/nasa-svs-4953.html",
        ROOT / "Scripts/reference-data/sources/nasa-svs-5672.html",
        ROOT / "Scripts/record-eclipse-event-evidence.py",
        ROOT / "Scripts/eclipse-data/native-captures.json",
    ]
    return {
        str(path.relative_to(ROOT)): hashlib.sha256(
            capture_bytes if path == CAPTURES and capture_bytes is not None else path.read_bytes()
        ).hexdigest()
        for path in sorted(paths)
    }


def finite(value):
    if isinstance(value, dict):
        return all(finite(item) for item in value.values())
    if isinstance(value, list):
        return all(finite(item) for item in value)
    return not isinstance(value, (int, float)) or math.isfinite(value)


def near(first, second):
    if isinstance(first, dict):
        return first.keys() == second.keys() and all(near(first[key], second[key]) for key in first)
    if isinstance(first, list):
        return len(first) == len(second) and all(near(a, b) for a, b in zip(first, second))
    if isinstance(first, float):
        return isinstance(second, (int, float)) and abs(first - second) <= max(1.0e-10, 16 * math.ulp(first))
    return first == second


def references():
    archive = json.loads((ROOT / "Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json").read_bytes())
    return {row["universalTime"]: row for row in archive["lunarEclipses"]}


def validate_published(rows):
    expected = references()
    if len(rows) != len(expected) or {row["sourceTime"] for row in rows} != set(expected):
        raise ValueError("lunar eclipse row selection differs")
    for row in rows:
        source = expected[row["sourceTime"]]
        fields = {
            "sourceTime", "kind", "peakResidualSeconds", "penumbralDurationMinutes",
            "partialDurationMinutes", "totalDurationMinutes", "obscuration",
        }
        if "penumbralSemiDurationMinutes" in source:
            fields.add("penumbralDurationResidualMinutes")
        if set(row) != fields or row["kind"] != source["kind"]:
            raise ValueError("lunar eclipse observation fields or type differ")
        if row["peakResidualSeconds"] > source["toleranceSeconds"]:
            raise ValueError("lunar eclipse peak criterion failed")
        if abs(row["partialDurationMinutes"] - source["partialSemiDurationMinutes"]) > source["durationToleranceMinutes"]:
            raise ValueError("lunar eclipse partial-duration criterion failed")
        if abs(row["totalDurationMinutes"] - source["totalSemiDurationMinutes"]) > source["durationToleranceMinutes"]:
            raise ValueError("lunar eclipse total-duration criterion failed")
        if "penumbralSemiDurationMinutes" in source:
            residual = abs(row["penumbralDurationMinutes"] - source["penumbralSemiDurationMinutes"])
            if abs(residual - row["penumbralDurationResidualMinutes"]) > 1.0e-10 or residual > source["durationToleranceMinutes"]:
                raise ValueError("lunar eclipse penumbral-duration criterion failed")
        if not 0 <= row["obscuration"] <= 1:
            raise ValueError("invalid lunar eclipse obscuration")


def validate_obscurations(rows):
    archive = json.loads((ROOT / "Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json").read_bytes())
    expected = {row["universalTimeSearchSeed"]: row for row in archive["lunarEclipseObscurations"]}
    if len(rows) != len(expected) or {row["sourceTimeSearchSeed"] for row in rows} != set(expected):
        raise ValueError("lunar obscuration row selection differs")
    for row in rows:
        if set(row) != {"sourceTimeSearchSeed", "nativePeakTT", "obscuration"} or not 0 <= row["obscuration"] <= 1:
            raise ValueError("invalid lunar obscuration observation")
        source = expected[row["sourceTimeSearchSeed"]]
        if not source["roundingLowerBound"] <= row["obscuration"] <= source["roundingUpperBound"]:
            raise ValueError("lunar obscuration print interval criterion failed")


def build_seconds(receipt):
    match = re.search(r"Build complete! \(([^ ]+) sec\)", receipt)
    if not match:
        raise ValueError("missing build duration")
    return float(match.group(1))


def evidence(captures, hashes):
    if not finite(captures):
        raise ValueError("nonfinite native eclipse observation")
    for configuration in ("debug", "release"):
        validate_published(captures[configuration]["published"])
        validate_obscurations(captures[configuration]["obscurations"])
    if not near(captures["debug"], captures["release"]):
        raise ValueError("Debug and Release lunar eclipse observations differ")
    resources = captures["resources"]
    if set(resources) != {
        "checksum", "coldSeconds", "host", "hundredEclipsesSeconds", "peakAfterColdBytes",
        "peakAfterWorkloadBytes", "peakBeforeBytes",
    }:
        raise ValueError("resource observation fields differ")
    peaks = [resources[key] for key in ("peakBeforeBytes", "peakAfterColdBytes", "peakAfterWorkloadBytes")]
    if peaks != sorted(peaks) or min(peaks) <= 0 or resources["coldSeconds"] < 0 or resources["hundredEclipsesSeconds"] < 0:
        raise ValueError("invalid resource observation")
    if any(value <= 0 for value in captures["releaseObjectBytes"].values()) or captures["releaseExecutableBytes"] <= 0:
        raise ValueError("invalid binary-size observation")
    release_rows = captures["release"]["published"]
    obscuration_references = {
        row["universalTimeSearchSeed"]: row
        for row in json.loads((ROOT / "Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json").read_bytes())["lunarEclipseObscurations"]
    }
    obscuration_rows = captures["release"]["obscurations"]
    return {
        "schemaVersion": 1,
        "sourceSHA256": hashes,
        "baselineRevision": captures["baselineRevision"],
        "toolchain": captures["toolchain"],
        "buildSeconds": {name: build_seconds(captures["buildReceipts"][name]) for name in ("debug", "release")},
        "releaseExecutableBytes": captures["releaseExecutableBytes"],
        "releaseObjectBytes": captures["releaseObjectBytes"],
        "resources": resources,
        "published": {
            "rows": len(release_rows),
            "maximumPeakResidualSeconds": max(row["peakResidualSeconds"] for row in release_rows),
            "maximumPenumbralDurationResidualMinutes": max(row.get("penumbralDurationResidualMinutes", 0) for row in release_rows),
            "maximumPartialDurationResidualMinutes": max(abs(row["partialDurationMinutes"] - references()[row["sourceTime"]]["partialSemiDurationMinutes"]) for row in release_rows),
            "maximumTotalDurationResidualMinutes": max(abs(row["totalDurationMinutes"] - references()[row["sourceTime"]]["totalSemiDurationMinutes"]) for row in release_rows),
            "obscurationRows": len(obscuration_rows),
            "maximumObscurationResidualFromPrintedFraction": max(abs(row["obscuration"] - obscuration_references[row["sourceTimeSearchSeed"]]["obscuration"]) for row in obscuration_rows),
            "minimumObscurationMarginInsidePrintInterval": min(min(row["obscuration"] - obscuration_references[row["sourceTimeSearchSeed"]]["roundingLowerBound"], obscuration_references[row["sourceTimeSearchSeed"]]["roundingUpperBound"] - row["obscuration"]) for row in obscuration_rows),
        },
        "criteria": "All six archived NASA eclipse types and peaks retain the existing 120-second allowance. Partial and total semidurations retain the existing two-minute allowance. Three Danjon-based NASA Five Millennium Catalog penumbral semidurations use the same two-minute allowance. Two direct NASA SVS Moon-disc obscurations fall inside their disclosed print-precision intervals. Strict analytic geometry tests cover no eclipse, penumbral, partial and total boundaries.",
        "limitations": "NASA lunar magnitude is a diameter fraction, not the native disc-area obscuration result. The SVS comparison intervals represent printed precision, not NASA uncertainty bounds or an engine accuracy policy. Public eclipse facades remain C-backed until #96. Runtime, memory, object and executable sizes are host observations, not portable ceilings.",
    }


def capture(directory):
    directory = Path(directory)
    release_products = ROOT / ".build/out/Products/Release/AstronomyKitTests.xctest/Contents/MacOS/AstronomyKitTests"
    release_objects = ROOT / ".build/out/Intermediates.noindex/AstronomyKit.build/Release/AstronomyKit-t.build/Objects-normal/arm64"
    return {
        "debug": {name: json.loads((directory / f"debug/{name}.json").read_bytes()) for name in ("published", "obscurations")},
        "release": {name: json.loads((directory / f"release/{name}.json").read_bytes()) for name in ("published", "obscurations")},
        "resources": json.loads((directory / "resources/resources.json").read_bytes()),
        "buildReceipts": {name: (directory / f"full-{name}.log").read_text() for name in ("debug", "release")},
        "baselineRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "toolchain": subprocess.check_output(["swift", "--version"], text=True).strip(),
        "releaseExecutableBytes": release_products.stat().st_size,
        "releaseObjectBytes": {
            "EngineEclipseEvents.o": (release_objects / "EngineEclipseEvents.o").stat().st_size,
            "EngineShadowGeometry.o": (release_objects / "EngineShadowGeometry.o").stat().st_size,
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    captures = capture(arguments.capture) if arguments.capture else json.loads(CAPTURES.read_bytes())
    capture_bytes = (json.dumps(captures, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()
    result = evidence(captures, source_hashes(capture_bytes if arguments.capture else None))
    if arguments.check:
        if json.loads(OUTPUT.read_bytes()) != result:
            raise SystemExit("recorded lunar eclipse evidence differs from source-bound captures")
    else:
        if arguments.capture:
            CAPTURES.parent.mkdir(parents=True, exist_ok=True)
            CAPTURES.write_bytes(capture_bytes)
        OUTPUT.write_text(json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n")
    print("native lunar eclipse evidence verified")


if __name__ == "__main__":
    main()
