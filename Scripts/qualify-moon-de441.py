#!/usr/bin/env python3
"""Compare compact Moon projections against every DE441 record in the accepted range."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import platform
import struct
import time


SPEC = importlib.util.spec_from_file_location("direct_de441", Path(__file__).with_name("assess-moon-de441.py"))
direct = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(direct)
ROOT = direct.ROOT
OUTPUT = ROOT / "Scripts/moon-data/de441-compact-evidence.json"
CHUNK_RECORDS = 8192
CANDIDATES = [
    {"name": f"degree-{degree}-float32", "degree": degree, "encoding": "float32", "bytesPerCoefficient": 4}
    for degree in (3, 5, 7)
] + [{"name": "degree-5-int16", "degree": 5, "encoding": "int16", "bytesPerCoefficient": 2,
      "scalesKm": [16.0, 8.0, 1.0, 0.125, 0.015625, 0.001953125]},
    {"name": "degree-5-shared-endpoints", "degree": 5, "encoding": "hermite-float32", "recordBytes": 48}]


def up(value):
    return math.nextafter(value, math.inf)


def down(value):
    return math.nextafter(value, -math.inf)


def norm_upper(values):
    return up(math.sqrt(up(math.fsum(up(value * value) for value in values))))


def norm_lower(values):
    return down(math.sqrt(max(0.0, down(math.fsum(down(value * value) for value in values)))))


class CachedReader:
    """Cache verified official byte ranges; a saved manifest pins repeat runs."""

    def __init__(self, directory, expected=None):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.expected = expected or {}
        self.ranges = {}

    def read(self, start, count):
        key = f"{start}-{start + count - 1}"
        path = self.directory / f"{key}.bin"
        receipt = path.with_suffix(".json")
        if path.exists():
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            if key in self.expected:
                if digest != self.expected[key]:
                    raise ValueError(f"cached source digest differs: {key}")
            else:
                if not receipt.exists() or json.loads(receipt.read_text()) != {"sha256": digest, "identity": identity()}:
                    raise ValueError(f"cached source digest or identity differs: {key}")
        else:
            reader = direct.RangeReader(direct.SOURCE_URL)
            data = reader.read(start, count)
            if [reader.total_bytes, reader.etag, reader.last_modified] != identity():
                raise ValueError("official DE441 HTTP identity changed")
            digest = hashlib.sha256(data).hexdigest()
            if key in self.expected and digest != self.expected[key]:
                raise ValueError(f"downloaded source digest differs: {key}")
            path.write_bytes(data)
            receipt.write_text(json.dumps({"sha256": digest, "identity": identity()}))
        if len(data) != count:
            raise ValueError(f"short source range: {key}")
        self.ranges[key] = digest
        return data


def identity():
    return [direct.SOURCE_BYTES, direct.SOURCE_ETAG, direct.SOURCE_LAST_MODIFIED]


def float32_values(values):
    data = struct.pack(f"<{len(values)}f", *values)
    return struct.unpack(f"<{len(values)}f", data), data


def endpoint_projection(source, left):
    source_ends = endpoints(source)
    if left is None:
        left = source_ends[0]
    left_values, _ = float32_values([*left[0], *left[1]])
    right = source_ends[1]
    values, data = float32_values([*right[0], *right[1], *[value for axis in source for value in axis[4:6]]])
    result = []
    for axis in range(3):
        # P(+/-1), dP/dx(+/-1), c4 and c5 uniquely determine a quintic.
        pl, vl = left_values[axis], left_values[axis + 3]
        pr, vr = values[axis], values[axis + 3]
        c4, c5 = values[6 + 2 * axis:8 + 2 * axis]
        even = (pr + pl) / 2
        odd = (pr - pl) / 2
        c2 = ((vr - vl) - 16 * c4) / 4
        c3 = ((vr + vl) - odd - 24 * c5) / 8
        result.append([even - c2 - c4, odd - c3 - c5, c2, c3, c4, c5])
    return result, data


def project(source, candidate, left=None):
    if candidate["encoding"] == "hermite-float32":
        return endpoint_projection(source, left)
    count = candidate["degree"] + 1
    flat = [value for axis in source for value in axis[:count]]
    if candidate["encoding"] == "float32":
        values, data = float32_values(flat)
    else:
        scales = candidate["scalesKm"]
        integers = [round(value / scales[index % count]) for index, value in enumerate(flat)]
        if any(value < -32768 or value > 32767 for value in integers):
            raise ValueError("fixed-point coefficient overflow")
        data = struct.pack(f"<{len(integers)}h", *integers)
        values = [value * scales[index % count] for index, value in enumerate(struct.unpack(f"<{len(integers)}h", data))]
    return [values[axis * count:(axis + 1) * count] for axis in range(3)], data


def error_bounds(source, compact):
    position = []
    rate = []
    for original, projected in zip(source, compact):
        # One ulp encloses the Moon-minus-Earth subtraction error; nextafter encloses this subtraction.
        errors = [up(up(abs(value - (projected[k] if k < len(projected) else 0.0))) + math.ulp(value)) for k, value in enumerate(original)]
        position.append(up(math.fsum(errors)))
        rate.append(up(math.fsum(up(error * (k * k / 2)) for k, error in enumerate(errors))))
    return norm_upper(position), norm_upper(rate)


def distance_lower_bound(source):
    constant = norm_lower([axis[0] for axis in source])
    tail = up(math.fsum(norm_upper([axis[k] for axis in source]) for k in range(1, len(source[0]))))
    subtraction_error = up(math.fsum(math.ulp(value) for axis in source for value in axis))
    return down(down(constant - tail) - subtraction_error)


def evaluate(coefficients, x):
    state = [direct.chebyshev_value_and_rate(axis, x, 4.0) for axis in coefficients]
    return tuple(axis[0] for axis in state), tuple(axis[1] for axis in state)


def endpoints(coefficients):
    return [
        (tuple(math.fsum(value * (sign ** k) for k, value in enumerate(axis)) for axis in coefficients),
         tuple(math.fsum(value * k * k * (sign ** (k - 1)) / 2 for k, value in enumerate(axis) if k) for axis in coefficients))
        for sign in (-1, 1)
    ]


def validate_record(moon, earth, expected_midpoint):
    if len(moon) != 41 or len(earth) != 41 or not all(math.isfinite(value) for value in (*moon, *earth)):
        raise ValueError("invalid source record shape or nonfinite value")
    if moon[:2] != earth[:2] or moon[:2] != (expected_midpoint, 172800.0):
        raise ValueError("source record epoch or radius differs from the four-day grid")


def layout(reader):
    segments = direct.read_segments(reader)
    windows, count, _ = direct.direct_layout(reader, segments)
    moons = sorted((s for s in segments if (s.center, s.target) == (3, 301)), key=lambda s: s.start_seconds_tdb)
    pairs = []
    for moon in moons:
        metadata = direct.read_metadata(reader, moon)
        if metadata.record_days != 4 or metadata.record_words != 41:
            raise ValueError("unexpected DE441 record shape")
        matching = [w for w in windows if metadata.start_jd_tdb <= w["startJulianDateTDB"] < metadata.start_jd_tdb + metadata.record_count * 4]
        if not matching:
            continue
        window = matching[0]
        earth = next(s for s in segments if (s.center, s.target, s.start_seconds_tdb, s.end_seconds_tdb) == (3, 399, moon.start_seconds_tdb, moon.end_seconds_tdb))
        pairs.append((moon, earth, metadata, window))
    for previous, following in zip(pairs, pairs[1:]):
        if previous[3]["exclusiveEndJulianDateTDB"] != following[3]["startJulianDateTDB"]:
            raise ValueError("source coverage gap or overlap")
    if count != 730501 or len(pairs) != 2:
        raise ValueError("accepted source layout changed")
    return pairs


def batches(pairs):
    for moon, earth, metadata, window in pairs:
        first = window["firstRecord"]
        for offset in range(0, window["recordCount"], CHUNK_RECORDS):
            index = first + offset
            count = min(CHUNK_RECORDS, window["recordCount"] - offset)
            yield metadata, index, count, [((segment.first_word - 1 + index * 41) * 8, count * 41 * 8) for segment in (moon, earth)]


def runtime_sample(records):
    observations = {}
    for name, coefficients in records.items():
        started = time.perf_counter()
        iterations = 20000
        checksum = math.fsum(evaluate(coefficients[index % len(coefficients)], (index % 101) / 50 - 1)[0][0] for index in range(iterations))
        elapsed = time.perf_counter() - started
        observations[name] = {"iterations": iterations, "seconds": elapsed, "evaluationsPerSecond": iterations / elapsed, "checksum": checksum}
    return observations


def generation_sample(source_records):
    observations = {}
    for candidate in [None, *CANDIDATES]:
        started = time.perf_counter()
        iterations = 10000
        encoded_bytes = 0
        for index in range(iterations):
            source = source_records[index % len(source_records)]
            if candidate is None:
                data = struct.pack("<39d", *[value for axis in source for value in axis])
            else:
                _, data = project(source, candidate)
            encoded_bytes += len(data)
        elapsed = time.perf_counter() - started
        observations[candidate["name"] if candidate else "direct-float64"] = {
            "iterations": iterations, "seconds": elapsed, "recordsPerSecond": iterations / elapsed, "encodedBytes": encoded_bytes}
    return observations


def build_evidence(cache):
    started = time.perf_counter()
    saved = json.loads(OUTPUT.read_bytes()) if OUTPUT.exists() else {}
    reader = CachedReader(cache / "ranges", saved.get("source", {}).get("retrievedByteRangesSHA256"))
    pairs = layout(reader)
    tasks = list(batches(pairs))
    requests = [request for *_, batch_ranges in tasks for request in batch_ranges]
    print(f"Retrieving/verifying {len(requests)} source ranges ({sum(count for _, count in requests)} bytes)", flush=True)
    with ThreadPoolExecutor(max_workers=6) as executor:
        for _ in executor.map(lambda request: reader.read(*request), requests):
            pass
    retrieval_seconds = time.perf_counter() - started
    print("Source ranges ready; scanning every record", flush=True)
    outputs = {}
    reports = {}
    samples = {"direct-float64": []}
    previous = {}
    global_minimum = math.inf
    reference_vectors = direct.parse_horizons_vectors(direct.REFERENCE.read_bytes())
    references = {candidate["name"]: [] for candidate in CANDIDATES}
    boundary_epochs = [direct.J2000 + day for day in (-36556.5, -36524.5, 47846.5, 47878.5)] + [pairs[1][3]["startJulianDateTDB"]]
    boundary_records = []
    scan_started = time.perf_counter()
    for candidate in CANDIDATES:
        name = candidate["name"]
        outputs[name] = (cache / f"{name}.bin").open("wb")
        samples[name] = []
        reports[name] = {**candidate, "recordCount": 0, "maximumPositionBoundKm": 0.0, "maximumRateBoundKmPerDay": 0.0,
                         "maximumAngularBoundArcminutes": 0.0, "failedRecordCount": 0, "firstFailedRecords": [],
                         "maximumBoundaryPositionJumpKm": 0.0, "maximumBoundaryRateJumpKmPerDay": 0.0}
    source_jumps = {"maximumPositionJumpKm": 0.0, "maximumRateJumpKmPerDay": 0.0, "boundaryCount": 0}
    scanned = 0
    try:
        for metadata, first, count, ranges in tasks:
            moon_data, earth_data = (reader.read(*request) for request in ranges)
            for index, (moon, earth) in enumerate(zip(struct.iter_unpack("<41d", moon_data), struct.iter_unpack("<41d", earth_data))):
                start_jd = metadata.start_jd_tdb + (first + index) * 4
                midpoint = (start_jd + 2 - direct.J2000) * 86400
                validate_record(moon, earth, midpoint)
                source = [[moon[2 + axis * 13 + k] - earth[2 + axis * 13 + k] for k in range(13)] for axis in range(3)]
                minimum = distance_lower_bound(source)
                if minimum <= 0:
                    raise ValueError(f"nonpositive distance lower bound at {start_jd}")
                global_minimum = min(global_minimum, minimum)
                source_ends = endpoints(source)
                shared_left = previous["source"][1] if "source" in previous else source_ends[0]
                if "source" in previous:
                    prior_jd, prior = previous["source"]
                    if start_jd != prior_jd + 4:
                        raise ValueError("noncontiguous record grid")
                    source_jumps["boundaryCount"] += 1
                    source_jumps["maximumPositionJumpKm"] = max(source_jumps["maximumPositionJumpKm"], math.dist(prior[0], source_ends[0][0]))
                    source_jumps["maximumRateJumpKmPerDay"] = max(source_jumps["maximumRateJumpKmPerDay"], math.dist(prior[1], source_ends[0][1]))
                previous["source"] = start_jd, source_ends[1]
                selected = [v for v in reference_vectors if start_jd <= v.julian_date_tdb < start_jd + 4]
                if any(start_jd <= epoch <= start_jd + 4 for epoch in boundary_epochs):
                    boundary_records.append({"startJulianDateTDB": start_jd, "minimumRangeBoundKm": minimum})
                if scanned % 10000 == 0:
                    samples["direct-float64"].append(source)
                for candidate in CANDIDATES:
                    name = candidate["name"]
                    compact, data = project(source, candidate, shared_left)
                    if candidate["encoding"] == "hermite-float32" and scanned == 0:
                        outputs[name].write(float32_values([*shared_left[0], *shared_left[1]])[1])
                    outputs[name].write(data)
                    report = reports[name]
                    p_bound, v_bound = error_bounds(source, compact)
                    # atan/asin rounding does not participate in pass/fail: compare conservative E/r with a downward one-arcminute sine.
                    ratio = up(p_bound / minimum)
                    angle = up(math.asin(min(1.0, ratio)) * (10800 / math.pi))
                    for field, value in (("maximumPositionBoundKm", p_bound), ("maximumRateBoundKmPerDay", v_bound), ("maximumAngularBoundArcminutes", angle)):
                        if value > report[field]:
                            report[field] = value
                            report[field + "AtRecordStartJD"] = start_jd
                    if ratio >= down(math.sin(math.pi / 10800)):
                        report["failedRecordCount"] += 1
                        if len(report["firstFailedRecords"]) < 5:
                            report["firstFailedRecords"].append(start_jd)
                    ends = endpoints(compact)
                    if name in previous:
                        report["maximumBoundaryPositionJumpKm"] = max(report["maximumBoundaryPositionJumpKm"], math.dist(previous[name][0], ends[0][0]))
                        report["maximumBoundaryRateJumpKmPerDay"] = max(report["maximumBoundaryRateJumpKmPerDay"], math.dist(previous[name][1], ends[0][1]))
                    previous[name] = ends[1]
                    report["recordCount"] += 1
                    if scanned % 10000 == 0:
                        samples[name].append(compact)
                    for vector in selected:
                        p, v = evaluate(compact, (vector.julian_date_tdb - start_jd - 2) / 2)
                        references[name].append({"julianDateTDB": vector.julian_date_tdb,
                            "positionDifferenceKm": math.dist(p, tuple(a * direct.AU_KM for a in vector.position_au)),
                            "rateDifferenceKmPerDay": math.dist(v, tuple(a * direct.AU_KM for a in vector.velocity_au_per_day))})
                scanned += 1
            print(f"Scanned {scanned}/730501", flush=True)
    finally:
        for output in outputs.values():
            output.close()
    if scanned != 730501 or source_jumps["boundaryCount"] != scanned - 1:
        raise ValueError("incomplete full-range scan")
    scan_seconds = time.perf_counter() - scan_started
    for report in reports.values():
        path = cache / f"{report['name']}.bin"
        report["encodedBytes"] = path.stat().st_size
        report["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        report["passesRepresentationTarget"] = report["failedRecordCount"] == 0
        report["archivedHorizons"] = references[report["name"]]
        if len(report["archivedHorizons"]) != len(reference_vectors):
            raise ValueError("incomplete archived reference comparison")
    return {"schemaVersion": 1,
        "source": {"url": direct.SOURCE_URL, "identity": identity(), "globalDigestVerified": False,
                   "retrievedByteRangesSHA256": dict(sorted(reader.ranges.items(), key=lambda item: int(item[0].split("-")[0]))),
                   "frame": "ICRF", "time": "TDB", "state": "geometric Moon (301) minus Earth (399), km; analytic velocity in km per TDB day"},
        "coverage": {"ttDaysFromJ2000Inclusive": [-direct.ACCEPTED_TT_DAYS, direct.ACCEPTED_TT_DAYS], "tdbMarginDays": direct.TDB_TT_MARGIN_DAYS,
                     "segments": [{**pair[3], "firstRecordStartJulianDateTDB": pair[2].start_jd_tdb + pair[3]["firstRecord"] * 4} for pair in pairs], "recordCount": scanned, "minimumRangeLowerBoundKm": global_minimum,
                     "specialBoundaryRecords": boundary_records, "sourceBoundaryDiagnostics": source_jumps},
        "method": {"projection": "retain low-degree source Chebyshev coefficients, then quantize; the shared-endpoint quintic instead retains c4/c5 and matches shared Float32 position/rate nodes; no sampled fit",
                   "bounds": "coefficient absolute-error sums using |T_n| <= 1 and |T_n prime| <= n^2 on [-1,1]; derivative scale 2/4 days",
                   "distance": "norm(c_0) minus sum of norms(c_n), reduced by coefficient subtraction roundoff",
                   "rounding": "binary64 IEEE-754, math.fsum and one-ulp outward steps for bounds; one ulp per source coefficient subtraction; bounds apply to exact decoded polynomials, excluding runtime evaluator roundoff",
                   "angular": "asin(position bound / distance lower bound); one-arcminute sine comparison determines pass/fail",
                   "selection": "all source records, every adjacent boundary, all 30 archived Horizons epochs; special boundary records include the source split and both ends of each current DE440 blend",
                   "binary": "little endian, chronological records across both segments; ordinary candidates store axis-major coefficients without a header; shared-endpoint candidate starts with six Float32 left-node values, then each 48-byte record stores right position xyz, right rate xyz, and c4/c5 for x/y/z as Float32; the preceding right node supplies the next left node; per-segment first record epoch and counts are in coverage",
                   "independentReferenceSHA256": hashlib.sha256(direct.REFERENCE.read_bytes()).hexdigest()},
        "candidates": list(reports.values()),
        "directComparison": {"float64Bytes": scanned * 39 * 8, "float32Bytes": scanned * 39 * 4},
        "observations": {"host": platform.platform(), "python": platform.python_version(), "sourceRetrievalOrCacheVerificationSeconds": retrieval_seconds,
                         "generationAndQualificationSeconds": scan_seconds, "evaluator": "same Python math.fsum Chebyshev value and analytic derivative evaluator for all candidates; warm coefficients; decoding and I/O excluded",
                         "runtime": runtime_sample(samples), "encoding": generation_sample(samples["direct-float64"]), "productionRepresentative": False},
        "assessment": {"fullSourceRangeScanned": True, "productionIntegrated": False, "endToEndAccuracyQualified": False,
                       "decision": "Compare representation bounds, storage and boundary jumps before choosing integration; Python timings do not select the production representation.",
                       "remaining": "Swift encoding/evaluation and memory/runtime measurements, continuity handling, TT-to-TDB/frame transforms, independent end-to-end positions/states/events across the accepted range"}}


def comparable(evidence):
    evidence = json.loads(json.dumps(evidence))
    observations = evidence.pop("observations")
    evidence["runtimeChecksums"] = {name: value["checksum"] for name, value in observations["runtime"].items()}
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".context/issue-184/compact")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    evidence = build_evidence(args.cache)
    if args.check:
        if comparable(evidence) != comparable(json.loads(OUTPUT.read_bytes())):
            raise SystemExit("DE441 compact evidence differs")
        print("Verified full-range DE441 compact evidence")
    else:
        OUTPUT.write_bytes(direct.encoded(evidence))
        print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
