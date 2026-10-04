#!/usr/bin/env python3

import argparse
import hashlib
import json
import math
import platform
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT / "Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json"
MANIFEST = ROOT / "Tests/AstronomyKitTests/Fixtures/IndependentReferences/manifest.json"
PROBE = ROOT / "Scripts/reference-data/apparent-range-probe.c"
ENGINE = ROOT / "Sources/CLibAstronomy/astronomy.c"
HEADER = ROOT / "Sources/CLibAstronomy/include/astronomy.h"
EVIDENCE = ROOT / "Documentation/Migration/apparent-range-investigation.json"
AU_KM = 149_597_870.7
CONFIGURATIONS = (
    ("jpl-horizons", "corrected"),
    ("jpl-horizons", "uncorrected"),
    ("espenak-meeus", "corrected"),
    ("espenak-meeus", "uncorrected"),
)


def canonical_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def input_paths():
    paths = [Path(__file__), PROBE, ENGINE, HEADER, ARCHIVE, MANIFEST]
    for name in ("moon-observer", "mars-observer", "pluto-observer", "mercury-station"):
        paths.append(ROOT / f"Scripts/reference-data/sources/horizons/{name}.json")
        paths.append(ROOT / f"Scripts/reference-data/sources/horizons/{name}.query.json")
    return paths


def compile_probe(output):
    subprocess.run(
        [
            "cc", "-O2", "-std=c11", "-pthread",
            "-I", str(HEADER.parent),
            str(ENGINE), str(PROBE), "-lm", "-o", str(output),
        ],
        cwd=ROOT,
        check=True,
    )


def date_parts(text):
    year_text, month_text, rest = text.split("-", 2)
    month = {
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
        "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
    }[month_text]
    day_text, clock = rest.split(" ", 1)
    hour_text, minute_text, second_text = clock.split(":")
    if hour_text != "00" or minute_text != "00":
        raise ValueError(f"unsupported non-midnight observation: {text}")
    return int(year_text), month, int(day_text), float(second_text)


def run_probe(binary, observation, delta_t_model, aberration):
    year, month, day, second = date_parts(observation["utc"])
    completed = subprocess.run(
        [
            str(binary), observation["body"], delta_t_model, aberration,
            str(year), str(month), str(day), repr(second),
        ],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    return json.loads(completed.stdout)


def build_report(repository_revision=None):
    archive = json.loads(ARCHIVE.read_text())
    results = []
    with tempfile.TemporaryDirectory(prefix="astronomykit-apparent-range-") as directory:
        binary = Path(directory) / "probe"
        compile_probe(binary)
        for observation in archive["observations"]:
            configurations = []
            reference = observation["apparentRangeAU"]
            for delta_t_model, aberration in CONFIGURATIONS:
                actual = run_probe(binary, observation, delta_t_model, aberration)
                difference_au = actual["distanceAU"] - reference
                configurations.append(
                    {
                        "aberration": aberration,
                        "absoluteDifferenceAU": abs(difference_au),
                        "absoluteDifferenceKM": abs(difference_au) * AU_KM,
                        "astronomyRangeAU": actual["distanceAU"],
                        "deltaTModel": delta_t_model,
                        "signedDifferenceAU": difference_au,
                        "terrestrialTimeDaysSinceJ2000": actual["tt"],
                        "universalTimeDaysSinceJ2000": actual["ut"],
                    }
                )
            results.append(
                {
                    "body": observation["body"],
                    "comparisonClassification": "unmatched-no-light-time-backdating" if observation["body"] == "moon" else "light-time-convention-aligned",
                    "configurations": configurations,
                    "productionAppliesLightTimeBackdating": observation["body"] != "moon",
                    "referenceRangeAU": reference,
                    "series": observation["series"],
                    "utc": observation["utc"],
                }
            )
    selected = [
        configuration
        for result in results
        for configuration in result["configurations"]
        if configuration["deltaTModel"] == "jpl-horizons" and configuration["aberration"] == "uncorrected"
    ]
    return {
        "conclusion": "No cited primary source supplies a tolerance applicable to AstronomyKit for these apparent-range samples; residuals are diagnostic observations, not accuracy assertions.",
        "environment": {
            "compiler": subprocess.check_output(["cc", "--version"], text=True).splitlines()[0],
            "machine": platform.machine(),
            "operatingSystem": platform.platform(),
        },
        "inputSHA256": {str(path.relative_to(ROOT)): sha256(path) for path in input_paths()},
        "primarySources": [
            {
                "claim": "Horizons quantity 20 is observer-relative apparent range with light-time aberration, in AU.",
                "url": "https://ssd.jpl.nasa.gov/horizons/manual.html#obsquan",
            },
            {
                "claim": "Major-planet ephemeris uncertainty depends on body and time and spans meters to more than 1000 km; printed digits are not an accuracy guarantee.",
                "url": "https://ssd.jpl.nasa.gov/horizons/manual.html",
            },
            {
                "claim": "DE440 observational residuals describe the JPL ephemeris fit and do not define an error allowance for AstronomyKit's model.",
                "url": "https://ssd.jpl.nasa.gov/doc/Park.2021.AJ.DE440.pdf",
            },
        ],
        "repositoryRevisionAtMeasurement": repository_revision or subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "rangeSemantics": "For Mercury, Mars, and Pluto, the selected production C-core probe applies down-leg light time with Astronomy_GeoVector and disables its separate stellar-aberration correction to match Horizons quantity 20. Astronomy_GeoVector routes the Moon directly to Astronomy_GeoMoon without light-time backdating or aberration, so the three lunar residuals are unmatched diagnostic observations. Public Swift wrapper behavior is exercised separately by AuditValidationTests.",
        "results": results,
        "schemaVersion": 1,
        "selectedConfiguration": {"aberration": "uncorrected", "deltaTModel": "jpl-horizons"},
        "selectedMaximumAbsoluteDifferenceAU": max(item["absoluteDifferenceAU"] for item in selected),
        "selectedMaximumAbsoluteDifferenceKM": max(item["absoluteDifferenceKM"] for item in selected),
        "status": "diagnostic-without-applicable-tolerance",
    }


def validate_report(report):
    if report.get("status") != "diagnostic-without-applicable-tolerance":
        raise ValueError("report status must preserve the unresolved tolerance gap")
    recorded_inputs = report.get("inputSHA256", {})
    expected_inputs = {str(path.relative_to(ROOT)): sha256(path) for path in input_paths()}
    if recorded_inputs != expected_inputs:
        raise ValueError("report input hashes do not match the investigation inputs")
    maximum = 0.0
    for result in report.get("results", []):
        reference = result["referenceRangeAU"]
        if not math.isfinite(reference) or reference <= 0:
            raise ValueError("reference range must be a positive finite AU value")
        if result["body"] == "moon":
            if result["productionAppliesLightTimeBackdating"] or result["comparisonClassification"] != "unmatched-no-light-time-backdating":
                raise ValueError("Moon must remain classified as an unmatched non-backdated diagnostic")
        elif not result["productionAppliesLightTimeBackdating"] or result["comparisonClassification"] != "light-time-convention-aligned":
            raise ValueError("planetary ranges must remain classified as light-time convention aligned")
        for configuration in result["configurations"]:
            difference = configuration["astronomyRangeAU"] - reference
            if not math.isclose(configuration["signedDifferenceAU"], difference, rel_tol=0, abs_tol=1e-18):
                raise ValueError("signed range difference is inconsistent")
            if not math.isclose(configuration["absoluteDifferenceAU"], abs(difference), rel_tol=0, abs_tol=1e-18):
                raise ValueError("absolute AU range difference is inconsistent")
            if not math.isclose(configuration["absoluteDifferenceKM"], abs(difference) * AU_KM, rel_tol=0, abs_tol=1e-6):
                raise ValueError("range unit conversion is inconsistent")
            if configuration["deltaTModel"] == "jpl-horizons" and configuration["aberration"] == "uncorrected":
                maximum = max(maximum, abs(difference))
    if len(report.get("results", [])) != 12:
        raise ValueError("report must cover all 12 archived observer samples")
    if not math.isclose(report["selectedMaximumAbsoluteDifferenceAU"], maximum, rel_tol=0, abs_tol=1e-18):
        raise ValueError("selected maximum AU difference is inconsistent")
    if not math.isclose(report["selectedMaximumAbsoluteDifferenceKM"], maximum * AU_KM, rel_tol=0, abs_tol=1e-6):
        raise ValueError("selected maximum kilometer difference is inconsistent")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    repository_revision = None
    if args.check and EVIDENCE.exists():
        repository_revision = json.loads(EVIDENCE.read_text()).get("repositoryRevisionAtMeasurement")
    report = build_report(repository_revision=repository_revision)
    validate_report(report)
    encoded = canonical_bytes(report)
    if args.check:
        if not EVIDENCE.exists() or EVIDENCE.read_bytes() != encoded:
            raise SystemExit("apparent-range investigation evidence is stale")
        print("verified apparent-range investigation evidence")
    else:
        EVIDENCE.write_bytes(encoded)
        print(f"wrote {EVIDENCE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
