#!/usr/bin/env python3
"""Reproduce retained direct-source Moon fixtures from the pinned DE441 ranges."""
import argparse
import hashlib
import importlib.util
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Scripts/moon-data/de441-compact-evidence.json"
OUTPUT = ROOT / "Scripts/moon-data/de441-native-fixtures.json"


def reference_fixtures(cache):
    spec = importlib.util.spec_from_file_location("qualification", ROOT / "Scripts/qualify-moon-de441.py")
    q = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(q)
    evidence = json.loads(MANIFEST.read_bytes())
    reader = q.CachedReader(cache / "ranges", evidence["source"]["retrievedByteRangesSHA256"])
    count = evidence["coverage"]["recordCount"]
    start = evidence["coverage"]["segments"][0]["firstRecordStartJulianDateTDB"]
    chosen = {index * (count - 1) // 256 for index in range(257)}
    for candidate in evidence["candidates"]:
        for key, value in candidate.items():
            if key.endswith("AtRecordStartJD"):
                chosen.add(round((value - start) / 4))
    for row in evidence["coverage"]["specialBoundaryRecords"]:
        chosen.add(round((row["startJulianDateTDB"] - start) / 4))
    rows = []
    global_index = 0
    for metadata, first, batch_count, ranges in q.batches(q.layout(reader)):
        indices = sorted(i - global_index for i in chosen if global_index <= i < global_index + batch_count)
        if indices:
            moon_data, earth_data = (reader.read(*r) for r in ranges)
            for index in indices:
                moon, earth = (struct.unpack_from("<41d", data, index * 41 * 8) for data in (moon_data, earth_data))
                source = [[moon[2 + axis * 13 + k] - earth[2 + axis * 13 + k] for k in range(13)] for axis in range(3)]
                for x in (-1.0, -0.5, 0.0, 0.5, 1.0):
                    position, velocity = q.evaluate(source, x)
                    rows.append({"record": global_index + index, "x": x, "positionKm": position, "velocityKmPerTDBDay": velocity})
        global_index += batch_count
    result = {"sourceEvidenceSHA256": hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
              "selection": "257 uniformly spaced record indices, all candidate worst-bound records and all existing transition records; x=-1,-0.5,0,0.5,1 in every selected record",
              "recordCount": len(chosen), "rows": rows}
    path = ROOT / "Scripts/moon-data/de441-native-fixtures.json"
    data = q.direct.encoded(result)
    check(data)
    path.write_bytes(data)
    print(f"Wrote {len(rows)} direct-source state fixtures")


def check(raw=None):
    raw = OUTPUT.read_bytes() if raw is None else raw
    data = json.loads(raw)
    if data["sourceEvidenceSHA256"] != hashlib.sha256(MANIFEST.read_bytes()).hexdigest():
        raise ValueError("Direct source fixture provenance differs")
    if data["recordCount"] != 273 or len(data["rows"]) != 1365:
        raise ValueError("Direct source fixture inventory differs")
    if {(row["record"], row["x"]) for row in data["rows"]} != {(record, x) for record in {r["record"] for r in data["rows"]} for x in (-1, -.5, 0, .5, 1)}:
        raise ValueError("Direct source fixture phases differ")
    if hashlib.sha256(raw).hexdigest() != "460f1f9a8b8abf7ef558443786bf39e270d5be883ab793475656f16711ceae3c":
        raise ValueError("Direct source fixture digest differs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--cache", type=Path, default=ROOT / ".context/issue-184/compact")
    args = parser.parse_args()
    if args.check:
        check()
        print("Verified retained direct-source Moon fixtures")
    else:
        reference_fixtures(args.cache)


if __name__ == "__main__":
    main()
