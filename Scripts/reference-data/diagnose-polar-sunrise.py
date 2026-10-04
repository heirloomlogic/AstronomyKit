#!/usr/bin/env python3
"""Reproduce and isolate the archived South Pole sunrise residual."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
ARCHIVE_SPEC = importlib.util.spec_from_file_location('source_archive', Path(__file__).with_name('source_archive.py'))
source_archive = importlib.util.module_from_spec(ARCHIVE_SPEC)
ARCHIVE_SPEC.loader.exec_module(source_archive)


ROOT = Path(__file__).resolve().parents[2]
CURRENT_REVISION = "2ef43fe79a24d92090ce272ef69790228d3cedf9"
CURRENT_SOURCE = ROOT / "Sources/CLibAstronomy/astronomy.c"
CURRENT_HEADER = ROOT / "Sources/CLibAstronomy/include/astronomy.h"
CURRENT_SOURCE_GIT_BLOB = "34771ff93a1d07ab09ea5e00f5b5b9bf81087507"
CURRENT_SOURCE_SHA256 = "40c9c17447a2725fd6002f7e450612e9ca149becf9617e71fa57fefca0f491ed"
CURRENT_HEADER_SHA256 = "86708c090b3a521b9016d8c8d5ac2244a1d75fcf4b651a8a526ec6e7e4927d44"
CURRENT_ASSETS = {
    ROOT / "Sources/CLibAstronomy/polynomial.h": "bbb51a7fea1738f4f6dd029842da31a678891518930735d386b797f79e638783",
    ROOT / "Sources/CLibAstronomy/generated/polynomial-data.h": "689747697bf1b5f1f0f41dbdbab90a1dccfca5eb9ecbb4ba4d0a2162acfd54da",
    ROOT / "Sources/CLibAstronomy/generated/vsop87b_full.h": "a30509bde52487ccb13815b415c8d563511545cce3ba8259f86e007137b86d99",
    ROOT / "Sources/CLibAstronomy/generated/iau2000b_full.h": "969e564ac5173310bb7f730cf683de7a4975b3fcf20566f2a4b45755dcee41c1",
}
PINNED_REVISION = "865d3da7d8112bbc7911238052c6af4aaf877181"
PINNED_SOURCE = ROOT / "Scripts/reference-data/sources/astronomy-engine.c"
PINNED_HEADER = ROOT / "Scripts/reference-data/sources/astronomy-engine.h"
PINNED_SOURCE_SHA256 = "3ef243a3ee4c10fc05a5cb460d753e4e17eb2f57dad7892690e12599088717ac"
PINNED_HEADER_SHA256 = "0c130854ee55b466dee98928ad72e3c5092bc862d37a2bba036c5568c811edbe"
RISE_SET_SOURCE = ROOT / "Scripts/reference-data/sources/riseset.txt"
RISE_SET_SOURCE_SHA256 = "92f5c1edf647c3f46d8964cfab06315fbe09cb580bc512d1418d41039424ff48"
REPORT = ROOT / "Documentation/Migration/polar-sunrise-diagnosis.json"
VARIANT_NAMES = (
    "pinned",
    "current",
    "current-no-polynomial",
    "current-pinned-nutation",
    "current-no-polynomial-pinned-vsop",
    "current-no-polynomial-pinned-vsop-and-nutation",
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_verified_source(path: Path, expected_hash: str) -> str:
    data = source_archive.read_bytes(ROOT, path) if path.is_relative_to(ROOT) else path.read_bytes()
    actual_hash = sha256(data)
    if actual_hash != expected_hash:
        raise RuntimeError(f"source hash changed for {path}: expected {expected_hash}, got {actual_hash}")
    return data.decode()


def replace_function(source: str, signature: str, replacement: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    end = None
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    if end is None:
        raise RuntimeError(f"unterminated function: {signature}")
    return source[:start] + replacement.rstrip() + source[end:]


def disable_polynomial(source: str) -> str:
    replacements = (
        ("if (!PolynomialPosition((int)(model - vsop), time.tt, eclip, NULL))", "if (1) /* DIAGNOSTIC_POLYNOMIAL_DISABLED */"),
        ("if (PolynomialPosition((int)(model - vsop), tt, eclip, polynomial_velocity))", "if (0) /* DIAGNOSTIC_POLYNOMIAL_DISABLED */"),
        ("if (PolynomialPosition((int)(model - vsop), time.tt, polynomial_position, NULL))", "if (0) /* DIAGNOSTIC_POLYNOMIAL_DISABLED */"),
    )
    for old, new in replacements:
        if source.count(old) != 1:
            raise RuntimeError(f"polynomial control boundary changed: {old}")
        source = source.replace(old, new)
    return source


def pinned_nutation_function(pinned: str) -> str:
    start = pinned.index("static void iau2000b(astro_time_t *time)")
    brace = pinned.index("{", start)
    depth = 0
    for index in range(brace, len(pinned)):
        if pinned[index] == "{":
            depth += 1
        elif pinned[index] == "}":
            depth -= 1
            if depth == 0:
                return pinned[start : index + 1]
    raise RuntimeError("pinned nutation function is unterminated")


def exchange_nutation(current: str, pinned: str) -> str:
    return replace_function(current, "static void iau2000b(astro_time_t *time)", pinned_nutation_function(pinned))


def pinned_vsop_region(pinned: str) -> str:
    start = pinned.index("typedef struct\n{\n    double amplitude;")
    end = pinned.index("/** @cond DOXYGEN_SKIP */\n#define CalcEarth", start)
    return pinned[start:end]


def exchange_vsop(current: str, pinned: str) -> str:
    start = current.index('#include "generated/vsop87b_full.h"', current.index("/*------------------ VSOP ------------------*/"))
    end = current.index("/** @cond DOXYGEN_SKIP */\n#define CalcEarth", start)
    return current[:start] + pinned_vsop_region(pinned) + current[end:]


PROBE_SOURCE = r'''#include <stdio.h>
#include "astronomy.c"

typedef struct {
    int source_line;
    double latitude;
    int direction;
    int month;
    int day;
    int hour;
    int minute;
} probe_case_t;

static void emit_case(probe_case_t item, int first)
{
    const double tolerances[] = {10.0, 1.0, 0.1, 0.01};
    astro_observer_t observer = Astronomy_MakeObserver(item.latitude, 0.0, 0.0);
    astro_time_t start = Astronomy_MakeTime(2022, 1, 1, 0, 0, 0.0);
    astro_time_t expected = Astronomy_MakeTime(2022, item.month, item.day, item.hour, item.minute, 0.0);
    astro_search_result_t event = Astronomy_SearchRiseSet(BODY_SUN, observer, (astro_direction_t)item.direction, start, 366.0);
    astro_atmosphere_t atmos = Astronomy_Atmosphere(0.0);
    context_altitude_t context;
    astro_func_result_t at_expected;
    astro_func_result_t at_event;
    astro_func_result_t before;
    astro_func_result_t after;
    size_t index;
    if (event.status != ASTRO_SUCCESS || atmos.status != ASTRO_SUCCESS) {
        fprintf(stderr, "search failed for source line %d\n", item.source_line);
        exit(2);
    }
    context.body = BODY_SUN;
    context.direction = item.direction;
    context.observer = observer;
    context.body_radius_au = SUN_RADIUS_AU;
    context.target_altitude = HorizonDipAngle(observer, 0.0) - REFRACTION_NEAR_HORIZON * atmos.density;
    at_expected = altitude_diff(&context, expected);
    at_event = altitude_diff(&context, event.time);
    before = altitude_diff(&context, Astronomy_AddDays(event.time, -30.0 / 86400.0));
    after = altitude_diff(&context, Astronomy_AddDays(event.time, +30.0 / 86400.0));
    printf("%s{\"sourceLine\":%d,\"latitudeDegrees\":%.1f,\"direction\":\"%s\",", first ? "" : ",", item.source_line, item.latitude, item.direction == DIRECTION_RISE ? "rise" : "set");
    printf("\"expectedUT\":%.12f,\"expectedTT\":%.12f,\"eventUT\":%.12f,\"eventTT\":%.12f,", expected.ut, expected.tt, event.time.ut, event.time.tt);
    printf("\"utErrorSeconds\":%.6f,\"ttErrorSeconds\":%.6f,\"literalTTErrorSeconds\":%.6f,\"deltaTSeconds\":%.6f,", (event.time.ut - expected.ut) * 86400.0, (event.time.tt - expected.tt) * 86400.0, (event.time.tt - expected.ut) * 86400.0, (expected.tt - expected.ut) * 86400.0);
    printf("\"expectedAltitudeResidualDegrees\":%.12g,\"eventAltitudeResidualDegrees\":%.12g,\"altitudeSlopeDegreesPerSecond\":%.12g,", at_expected.value, at_event.value, (after.value - before.value) / 60.0);
    printf("\"rootConvergenceSeconds\":{");
    for (index = 0; index < sizeof(tolerances)/sizeof(tolerances[0]); ++index) {
        astro_time_t left = Astronomy_AddDays(event.time, -0.5);
        astro_time_t right = Astronomy_AddDays(event.time, +0.5);
        astro_search_result_t root = Astronomy_Search(altitude_diff, &context, left, right, tolerances[index]);
        if (root.status != ASTRO_SUCCESS) {
            fprintf(stderr, "root search failed for source line %d tolerance %.2f\n", item.source_line, tolerances[index]);
            exit(3);
        }
        printf("%s\"%.2f\":%.6f", index ? "," : "", tolerances[index], (root.time.ut - event.time.ut) * 86400.0);
    }
    printf("}}");
}

int main(void)
{
    const probe_case_t cases[] = {
        {2922, -90.0, DIRECTION_SET, 3, 22, 18, 7},
        {2923, -90.0, DIRECTION_RISE, 9, 20, 21, 52},
        {5908, +90.0, DIRECTION_RISE, 3, 18, 13, 2},
        {5909, +90.0, DIRECTION_SET, 9, 25, 4, 13}
    };
    size_t index;
    Astronomy_SetDeltaTFunction(Astronomy_DeltaT_EspenakMeeus);
    printf("[");
    for (index = 0; index < sizeof(cases)/sizeof(cases[0]); ++index)
        emit_case(cases[index], index == 0);
    printf("]\n");
    return 0;
}
'''


def compile_and_run(source: str, header: str, current_assets: bool) -> list[dict[str, object]]:
    with tempfile.TemporaryDirectory(prefix="polar-sunrise-") as temporary:
        directory = Path(temporary)
        (directory / "astronomy.c").write_text(source)
        (directory / "astronomy.h").write_text(header)
        (directory / "probe.c").write_text(PROBE_SOURCE)
        if current_assets:
            shutil.copytree(ROOT / "Sources/CLibAstronomy/generated", directory / "generated")
            shutil.copy2(ROOT / "Sources/CLibAstronomy/polynomial.h", directory / "polynomial.h")
        executable = directory / "probe"
        command = ["cc", "-std=c11", "-O2", "-Wall", "-Wextra", "probe.c", "-lm", "-pthread", "-o", str(executable)]
        subprocess.run(command, cwd=directory, check=True, capture_output=True, text=True)
        completed = subprocess.run([str(executable)], cwd=directory, check=True, capture_output=True, text=True)
        return json.loads(completed.stdout)


def build_report() -> dict[str, object]:
    current = read_verified_source(CURRENT_SOURCE, CURRENT_SOURCE_SHA256)
    current_header = read_verified_source(CURRENT_HEADER, CURRENT_HEADER_SHA256)
    pinned = read_verified_source(PINNED_SOURCE, PINNED_SOURCE_SHA256)
    pinned_header = read_verified_source(PINNED_HEADER, PINNED_HEADER_SHA256)
    read_verified_source(RISE_SET_SOURCE, RISE_SET_SOURCE_SHA256)
    for path, expected_hash in CURRENT_ASSETS.items():
        read_verified_source(path, expected_hash)
    variants = {
        "pinned": compile_and_run(pinned, pinned_header, False),
        "current": compile_and_run(current, current_header, True),
        "current-no-polynomial": compile_and_run(disable_polynomial(current), current_header, True),
        "current-pinned-nutation": compile_and_run(exchange_nutation(current, pinned), current_header, True),
        "current-no-polynomial-pinned-vsop": compile_and_run(disable_polynomial(exchange_vsop(current, pinned)), current_header, True),
        "current-no-polynomial-pinned-vsop-and-nutation": compile_and_run(exchange_nutation(disable_polynomial(exchange_vsop(current, pinned)), pinned), current_header, True),
    }
    report = {
        "schemaVersion": 1,
        "comparisonRevision": CURRENT_REVISION,
        "pinnedRevision": PINNED_REVISION,
        "sources": {
            "currentAstronomyC": CURRENT_SOURCE_SHA256,
            "currentAstronomyCGitBlob": CURRENT_SOURCE_GIT_BLOB,
            "currentAstronomyH": CURRENT_HEADER_SHA256,
            "pinnedAstronomyC": PINNED_SOURCE_SHA256,
            "pinnedAstronomyH": PINNED_HEADER_SHA256,
            "riseSetTable": RISE_SET_SOURCE_SHA256,
            **{path.relative_to(ROOT).as_posix(): expected_hash for path, expected_hash in CURRENT_ASSETS.items()},
        },
        "compilerCommand": "cc -std=c11 -O2 -Wall -Wextra probe.c -lm -pthread",
        "controls": {
            "current-no-polynomial": "Disable the three PolynomialPosition branches in the temporary current source.",
            "current-pinned-nutation": "Replace only the temporary current iau2000b value function with the pinned function.",
            "current-no-polynomial-pinned-vsop": "Disable the polynomial branches and replace only the temporary current VSOP types, tables, and model registry with the pinned region.",
            "current-no-polynomial-pinned-vsop-and-nutation": "Apply the pinned VSOP and nutation exchanges together with the polynomial path disabled.",
        },
        "sourceURLs": {
            "pinnedAstronomyC": f"https://raw.githubusercontent.com/cosinekitty/astronomy/{PINNED_REVISION}/source/c/astronomy.c",
            "pinnedAstronomyH": f"https://raw.githubusercontent.com/cosinekitty/astronomy/{PINNED_REVISION}/source/c/astronomy.h",
        },
        "variants": {name: {"events": variants[name]} for name in VARIANT_NAMES},
    }
    validate_report(report)
    return report


def validate_report(report: dict[str, object]) -> None:
    variants = report.get("variants")
    if not isinstance(variants, dict) or set(variants) != set(VARIANT_NAMES):
        raise RuntimeError("report variant set does not match the required isolated controls")
    for name in VARIANT_NAMES:
        events = variants[name].get("events")
        if not isinstance(events, list) or [event.get("sourceLine") for event in events] != [2922, 2923, 5908, 5909]:
            raise RuntimeError(f"variant {name} does not contain all four polar events in source order")
    current_failure = next(event for event in variants["current"]["events"] if event["sourceLine"] == 2923)
    pinned_failure = next(event for event in variants["pinned"]["events"] if event["sourceLine"] == 2923)
    combined_failure = next(event for event in variants["current-no-polynomial-pinned-vsop-and-nutation"]["events"] if event["sourceLine"] == 2923)
    if not 75.9 < current_failure["ttErrorSeconds"] < 76.1:
        raise RuntimeError("current source no longer reproduces the archived source-line 2923 residual")
    if abs(combined_failure["ttErrorSeconds"] - pinned_failure["ttErrorSeconds"]) > 0.000001:
        raise RuntimeError("combined VSOP and nutation control no longer reproduces the pinned event time")
    if abs(current_failure["eventAltitudeResidualDegrees"]) > 0.000001:
        raise RuntimeError("current root residual exceeds the diagnostic bound")


def encoded(report: dict[str, object]) -> str:
    return json.dumps(report, indent=2, sort_keys=True) + "\n"


def check_report(path: Path, report: dict[str, object]) -> None:
    expected = encoded(report)
    if not path.exists() or path.read_text() != expected:
        raise RuntimeError(f"report is stale: run {Path(__file__).relative_to(ROOT)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail instead of replacing a stale report")
    arguments = parser.parse_args()
    report = build_report()
    if arguments.check:
        check_report(REPORT, report)
    else:
        REPORT.write_text(encoded(report))
        print(f"wrote {REPORT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
