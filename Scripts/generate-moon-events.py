#!/usr/bin/env python3
"""Freeze direct DE441 records for bounded native lunar event qualification."""
import argparse
import hashlib
import importlib.util
import json
import math
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "Scripts/moon-data/de441-compact-evidence.json"
OUTPUT = ROOT / "Scripts/moon-data/de441-event-fixtures.json"
FIXTURE_SHA256 = "94f77aad56bb3e136edcd7a04c04113f723cbd10371ea88c586f4504d2375ea6"


def windows():
    half_span = 1461000 - 32.25
    result = [{"id": f"uniform-{index:02d}", "startTT": -half_span + index * 2 * half_span / 16 - 32,
               "endTT": -half_span + index * 2 * half_span / 16 + 32} for index in range(17)]
    result += [{"id": "blend-1900", "startTT": -36588.5, "endTT": -36492.5},
               {"id": "blend-2131", "startTT": 47814.5, "endTT": 47910.5},
               {"id": "source-segment", "startTT": -11144.5, "endTT": -11080.5}]
    return result


def required_records(selected, start):
    result = set()
    for window in selected:
        first = math.floor((window["startTT"] - .01 - start) / 4)
        last = math.floor((window["endTT"] + .01 - start) / 4)
        result.update(range(first, last + 1))
    return result


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def generate(cache):
    spec = importlib.util.spec_from_file_location("qualification", ROOT / "Scripts/qualify-moon-de441.py")
    q = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(q)
    evidence = json.loads(EVIDENCE.read_bytes())
    reader = q.CachedReader(cache / "ranges", evidence["source"]["retrievedByteRangesSHA256"])
    start = evidence["coverage"]["segments"][0]["firstRecordStartJulianDateTDB"] - 2451545
    chosen = required_records(windows(), start)
    rows = []
    global_index = 0
    for _, _, count, ranges in q.batches(q.layout(reader)):
        selected = sorted(index - global_index for index in chosen if global_index <= index < global_index + count)
        if selected:
            data = [reader.read(*r) for r in ranges]
            for index in selected:
                moon, earth = (struct.unpack_from("<41d", item, index * 41 * 8) for item in data)
                coefficients = [[moon[2 + axis * 13 + k] - earth[2 + axis * 13 + k] for k in range(13)] for axis in range(3)]
                position, velocity = q.evaluate(coefficients, 0)
                rows.append({"index": global_index + index, "coefficientsKm": coefficients,
                             "midpointPositionKm": position, "midpointVelocityKmPerTDBDay": velocity})
        global_index += count
    if {row["index"] for row in rows} != chosen:
        raise ValueError("Source records do not cover every frozen window")
    return encoded({"schemaVersion": 1, "sourceEvidenceSHA256": hashlib.sha256(EVIDENCE.read_bytes()).hexdigest(),
                    "frame": "geometric geocentric ICRF", "timeScale": "coefficients TDB; windows TT days from J2000",
                    "sourceStartTDB": start, "recordDays": 4, "windows": windows(), "records": rows})


def check(data):
    if hashlib.sha256(data).hexdigest() != FIXTURE_SHA256:
        raise ValueError("Direct event fixture digest differs")
    value = json.loads(data)
    if value["sourceEvidenceSHA256"] != hashlib.sha256(EVIDENCE.read_bytes()).hexdigest():
        raise ValueError("Direct event fixture source evidence differs")
    if value["windows"] != windows() or {r["index"] for r in value["records"]} != required_records(windows(), value["sourceStartTDB"]):
        raise ValueError("Direct event fixture coverage differs")


def collect_results(prefix):
    results = {name: json.loads(Path(str(prefix) + "-" + name + ".json").read_bytes())
               for name in ("published", "source", "transitions")}
    summaries = {}
    for name in ("published", "source"):
        summaries[name] = {}
        for event in sorted({row["event"] for row in results[name]}):
            rows = [row for row in results[name] if row["event"] == event]
            summaries[name][event] = {"count": len(rows),
                                     "maximumAbsoluteResidualSeconds": max(abs(row["residualSeconds"]) for row in rows)}
    files = ["Scripts/generate-moon-events.py", "Scripts/moon-data/de441-event-fixtures.json",
             "Scripts/moon-data/de441-compact-evidence.json",
             "Tests/AstronomyKitTests/Engine/Moon/MoonEventQualification.swift",
             "Tests/AstronomyKitTests/Engine/Moon/EngineMoonEventQualificationTests.swift",
             "Tests/AstronomyKitTests/Engine/Moon/EngineLibrationTests.swift",
             "Tests/AstronomyKitTests/Fixtures/IndependentReferences/reference-fixtures.json"]
    result = {"schemaVersion": 1, "runtimeRevision": "805f90a366d832cca259654747e97e13b3ca6bf6",
              "toolchain": subprocess.check_output(["swift", "--version"], text=True, stderr=subprocess.STDOUT).strip(),
              "sourceSHA256": {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in files},
              "summaries": summaries, "results": results,
              "scope": "Published tolerances retain their existing reference scope. Broad-window shifts isolate the Moon with shared Sun, frame and time models; no universal event-time or velocity bound is inferred.",
              "remainingDependencies": ["#92 production search ports", "#96 public cutover", "#184 broader qualification and closure"]}
    path = ROOT / "Scripts/moon-data/de441-event-evidence.json"
    path.write_bytes(encoded(result))
    print("Recorded event evidence:", path.relative_to(ROOT))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".context/issue-184/compact")
    parser.add_argument("--check", action="store_true", help="verify the pinned committed fixture offline")
    parser.add_argument("--check-source", action="store_true", help="rebuild against the verified source cache and compare")
    parser.add_argument("--collect-results", type=Path, metavar="PREFIX", help="record PREFIX-published/source/transitions.json emitted by Swift tests")
    args = parser.parse_args()
    if args.collect_results:
        collect_results(args.collect_results)
        return
    if args.check:
        check(OUTPUT.read_bytes())
    elif args.check_source:
        if generate(args.cache) != OUTPUT.read_bytes():
            raise ValueError("Direct event fixture differs from verified source records")
    else:
        data = generate(args.cache)
        OUTPUT.write_bytes(data)
        print("Fixture SHA-256:", hashlib.sha256(data).hexdigest())
    print("Verified direct event fixtures" if args.check or args.check_source else "Generated direct event fixtures")


if __name__ == "__main__":
    main()
