#!/usr/bin/env python3
"""Measure a direct DE441 Moon-table candidate without downloading the 3.08 GiB kernel."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import time
from typing import NamedTuple
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = "https://ssd.jpl.nasa.gov/ftp/eph/planets/bsp/de441.bsp"
SOURCE_BYTES = 3_307_878_400
SOURCE_ETAG = '"5fe1446a-c52a3800"'
SOURCE_LAST_MODIFIED = "Tue, 22 Dec 2020 00:57:14 GMT"
REFERENCE = ROOT / "Scripts/reference-data/sources/horizons/moon-vector.json"
OUTPUT = ROOT / "Scripts/moon-data/de441-direct-evidence.json"
J2000 = 2_451_545.0
AU_KM = 149_597_870.7
SECONDS_PER_DAY = 86_400.0
ACCEPTED_TT_DAYS = 1_461_000.0
TDB_TT_MARGIN_DAYS = 2.2e-8


class Segment(NamedTuple):
    start_seconds_tdb: float
    end_seconds_tdb: float
    target: int
    center: int
    frame: int
    kind: int
    first_word: int
    last_word: int


class RecordMetadata(NamedTuple):
    start_jd_tdb: float
    record_days: float
    record_words: int
    record_count: int


class ReferenceVector(NamedTuple):
    julian_date_tdb: float
    position_au: tuple
    velocity_au_per_day: tuple


class RangeReader:
    def __init__(self, location):
        self.location = location
        self.ranges = {}
        self.cache = {}
        self.total_bytes = None
        self.etag = None
        self.last_modified = None

    def read(self, start, count):
        if start < 0 or count <= 0:
            raise ValueError("invalid byte range")
        if (start, count) in self.cache:
            return self.cache[(start, count)]
        if isinstance(self.location, Path):
            with self.location.open("rb") as source:
                source.seek(start)
                data = source.read(count)
            self.total_bytes = self.location.stat().st_size
        else:
            end = start + count - 1
            request = urllib.request.Request(self.location, headers={"Range": f"bytes={start}-{end}"})
            with urllib.request.urlopen(request) as response:
                data = response.read()
                content_range = response.headers.get("Content-Range")
                match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", content_range or "")
                if not match or tuple(map(int, match.groups()[:2])) != (start, end):
                    raise ValueError("source did not honor the requested byte range")
                self.total_bytes = int(match.group(3))
                self.etag = response.headers.get("ETag")
                self.last_modified = response.headers.get("Last-Modified")
        if len(data) != count:
            raise ValueError("source returned a short byte range")
        key = f"{start}-{start + count - 1}"
        self.ranges[key] = hashlib.sha256(data).hexdigest()
        self.cache[(start, count)] = data
        return data


def parse_summary_record(data):
    if len(data) != 1024:
        raise ValueError("SPK summary record must be 1024 bytes")
    following, _, count = struct.unpack_from("<3d", data)
    if count < 0 or count > 25 or count != int(count):
        raise ValueError("invalid SPK summary count")
    segments = []
    for index in range(int(count)):
        offset = 24 + index * 40
        start, end, target, center, frame, kind, first, last = struct.unpack_from("<2d6i", data, offset)
        segments.append(Segment(start, end, target, center, frame, kind, first, last))
    return int(following), segments


def read_segments(reader):
    header = reader.read(0, 1024)
    if header[:8] != b"DAF/SPK " or header[88:96] != b"LTL-IEEE":
        raise ValueError("source is not a little-endian DAF/SPK")
    if struct.unpack_from("<2i", header, 8) != (2, 6):
        raise ValueError("unexpected DAF/SPK summary format")
    record = struct.unpack_from("<i", header, 76)[0]
    segments = []
    seen = set()
    while record:
        if record in seen:
            raise ValueError("cyclic SPK summary list")
        seen.add(record)
        following, batch = parse_summary_record(reader.read((record - 1) * 1024, 1024))
        segments.extend(batch)
        record = following
    return segments


def read_metadata(reader, segment):
    if (segment.frame, segment.kind) != (1, 2):
        raise ValueError("expected a type-2 segment on ICRF axes")
    data = reader.read((segment.last_word - 4) * 8, 32)
    start_seconds, record_seconds, words, count = struct.unpack("<4d", data)
    if words != int(words) or count != int(count):
        raise ValueError("nonintegral type-2 record shape")
    return RecordMetadata(
        J2000 + start_seconds / SECONDS_PER_DAY,
        record_seconds / SECONDS_PER_DAY,
        int(words),
        int(count),
    )


def record_window(metadata, start_jd_tdb, exclusive_end_jd_tdb):
    segment_end = metadata.start_jd_tdb + metadata.record_days * metadata.record_count
    if not metadata.start_jd_tdb <= start_jd_tdb < exclusive_end_jd_tdb <= segment_end:
        raise ValueError("requested span is outside segment")
    first = math.floor((start_jd_tdb - metadata.start_jd_tdb) / metadata.record_days)
    last = math.ceil((exclusive_end_jd_tdb - metadata.start_jd_tdb) / metadata.record_days)
    return first, last - first


def parse_horizons_vectors(data):
    payload = json.loads(data)
    result = payload["result"]
    if "{source: DE441}" not in result or "Output type     : GEOMETRIC cartesian states" not in result or "Reference frame : ICRF" not in result:
        raise ValueError("Horizons archive is not geometric ICRF DE441")
    body = result.split("$$SOE", 1)[1].split("$$EOE", 1)[0]
    vectors = []
    for line in body.splitlines():
        fields = [field.strip() for field in line.split(",")]
        if len(fields) < 8:
            continue
        try:
            julian_date = float(fields[0])
            state = tuple(float(value) for value in fields[2:8])
        except ValueError:
            continue
        vectors.append(ReferenceVector(julian_date, state[:3], state[3:]))
    if not vectors:
        raise ValueError("Horizons archive has no vectors")
    return vectors


def stable_sum(values):
    return math.fsum(values)


def chebyshev_value_and_rate(coefficients, x, record_days):
    values = [1.0, x]
    derivatives = [0.0, 1.0]
    for _ in range(2, len(coefficients)):
        values.append(2 * x * values[-1] - values[-2])
        derivatives.append(2 * values[-2] + 2 * x * derivatives[-1] - derivatives[-2])
    value = stable_sum(coefficient * values[index] for index, coefficient in enumerate(coefficients))
    slope = stable_sum(coefficient * derivatives[index] for index, coefficient in enumerate(coefficients))
    return value, slope * 2 / record_days


def float32_with_bounds(coefficients, record_days):
    converted = tuple(struct.unpack("<f", struct.pack("<f", coefficient))[0] for coefficient in coefficients)
    errors = [abs(source - result) for source, result in zip(coefficients, converted)]
    position_bound = stable_sum(errors)
    rate_bound = stable_sum(error * degree * degree * 2 / record_days for degree, error in enumerate(errors))
    return converted, position_bound, rate_bound


def segment_for(segments, center, target, julian_date_tdb):
    seconds = (julian_date_tdb - J2000) * SECONDS_PER_DAY
    matches = [segment for segment in segments if segment.center == center and segment.target == target and segment.start_seconds_tdb <= seconds < segment.end_seconds_tdb]
    if len(matches) != 1:
        raise ValueError(f"expected one segment for {center}->{target} at JD {julian_date_tdb}, found {len(matches)}")
    return matches[0]


def record(reader, segment, metadata, julian_date_tdb):
    index = math.floor((julian_date_tdb - metadata.start_jd_tdb) / metadata.record_days)
    if index < 0 or index >= metadata.record_count:
        raise ValueError("epoch is outside segment records")
    data = reader.read((segment.first_word - 1 + index * metadata.record_words) * 8, metadata.record_words * 8)
    return struct.unpack(f"<{metadata.record_words}d", data)


def relative_coefficients(reader, segments, julian_date_tdb):
    moon_segment = segment_for(segments, 3, 301, julian_date_tdb)
    earth_segment = segment_for(segments, 3, 399, julian_date_tdb)
    moon_metadata = read_metadata(reader, moon_segment)
    earth_metadata = read_metadata(reader, earth_segment)
    if moon_metadata != earth_metadata or moon_metadata.record_words != 41:
        raise ValueError("Moon and Earth record grids differ")
    moon = record(reader, moon_segment, moon_metadata, julian_date_tdb)
    earth = record(reader, earth_segment, earth_metadata, julian_date_tdb)
    if moon[:2] != earth[:2]:
        raise ValueError("Moon and Earth record epochs differ")
    coefficients = tuple((moon[index] - earth[index]) / AU_KM for index in range(2, 41))
    x = ((julian_date_tdb - J2000) * SECONDS_PER_DAY - moon[0]) / moon[1]
    if not -1 <= x <= 1:
        raise ValueError("epoch is outside selected record")
    return moon_metadata, coefficients, x


def evaluate(coefficients, x, record_days):
    position = []
    velocity = []
    for axis in range(3):
        start = axis * 13
        value, rate = chebyshev_value_and_rate(coefficients[start:start + 13], x, record_days)
        position.append(value)
        velocity.append(rate)
    return tuple(position), tuple(velocity)


def norm(values):
    return math.sqrt(stable_sum(value * value for value in values))


def difference(left, right):
    return tuple(a - b for a, b in zip(left, right))


def direct_layout(reader, segments):
    lower = J2000 - ACCEPTED_TT_DAYS - TDB_TT_MARGIN_DAYS
    upper = J2000 + ACCEPTED_TT_DAYS + TDB_TT_MARGIN_DAYS
    pairs = []
    for segment in sorted((item for item in segments if (item.center, item.target) == (3, 301)), key=lambda item: item.start_seconds_tdb):
        metadata = read_metadata(reader, segment)
        earth_segments = [item for item in segments if (item.center, item.target, item.start_seconds_tdb, item.end_seconds_tdb) == (3, 399, segment.start_seconds_tdb, segment.end_seconds_tdb)]
        if len(earth_segments) != 1 or read_metadata(reader, earth_segments[0]) != metadata:
            raise ValueError("Moon and Earth segment grids differ")
        segment_start = metadata.start_jd_tdb
        segment_end = segment_start + metadata.record_days * metadata.record_count
        start = max(lower, segment_start)
        end = min(upper, segment_end)
        if start < end:
            first, count = record_window(metadata, start, end)
            pairs.append({"firstRecord": first, "recordCount": count, "startJulianDateTDB": start, "exclusiveEndJulianDateTDB": end})
    if not pairs or pairs[0]["startJulianDateTDB"] != lower or pairs[-1]["exclusiveEndJulianDateTDB"] != upper:
        raise ValueError("DE441 segments do not cover the accepted range")
    record_count = sum(item["recordCount"] for item in pairs)
    coefficient_count = record_count * 3 * 13
    return pairs, record_count, coefficient_count


def build_evidence(location=SOURCE_URL):
    reader = RangeReader(Path(location) if not str(location).startswith(("http://", "https://")) else location)
    segments = read_segments(reader)
    vectors = parse_horizons_vectors(REFERENCE.read_bytes())
    maximum_position_km = 0.0
    maximum_velocity_km_per_second = 0.0
    maximum_float32_position_component_au = 0.0
    maximum_float32_rate_component_au_per_day = 0.0
    records = []
    loaded = []
    for reference in vectors:
        metadata, coefficients, x = relative_coefficients(reader, segments, reference.julian_date_tdb)
        position, velocity = evaluate(coefficients, x, metadata.record_days)
        position_error = norm(difference(position, reference.position_au)) * AU_KM
        velocity_error = norm(difference(velocity, reference.velocity_au_per_day)) * AU_KM / SECONDS_PER_DAY
        maximum_position_km = max(maximum_position_km, position_error)
        maximum_velocity_km_per_second = max(maximum_velocity_km_per_second, velocity_error)
        position_bound = 0.0
        rate_bound = 0.0
        converted = []
        for axis in range(3):
            values, axis_position_bound, axis_rate_bound = float32_with_bounds(coefficients[axis * 13:(axis + 1) * 13], metadata.record_days)
            converted.extend(values)
            position_bound = max(position_bound, axis_position_bound)
            rate_bound = max(rate_bound, axis_rate_bound)
        maximum_float32_position_component_au = max(maximum_float32_position_component_au, position_bound)
        maximum_float32_rate_component_au_per_day = max(maximum_float32_rate_component_au_per_day, rate_bound)
        loaded.append((tuple(converted), x, metadata.record_days))
        records.append({"julianDateTDB": reference.julian_date_tdb, "positionDifferenceKm": position_error, "velocityDifferenceKmPerSecond": velocity_error})
    iterations = 100_000
    started = time.perf_counter()
    checksum = 0.0
    for index in range(iterations):
        coefficients, x, days = loaded[index % len(loaded)]
        checksum += evaluate(coefficients, x, days)[0][0]
    elapsed = time.perf_counter() - started
    layout, record_count, coefficient_count = direct_layout(reader, segments)
    if isinstance(reader.location, str):
        if (reader.total_bytes, reader.etag, reader.last_modified) != (SOURCE_BYTES, SOURCE_ETAG, SOURCE_LAST_MODIFIED):
            raise ValueError("published DE441 HTTP identity changed")
    minimum_range_au = min(norm(vector.position_au) for vector in vectors)
    sampled_angular_bound_arcminutes = math.asin(min(1.0, math.sqrt(3) * maximum_float32_position_component_au / minimum_range_au)) * 180 / math.pi * 60
    return {
        "schemaVersion": 1,
        "source": {
            "solution": "NASA/JPL DE441",
            "url": str(location),
            "bytes": reader.total_bytes,
            "etag": reader.etag,
            "lastModified": reader.last_modified,
            "retrievedByteRangesSHA256": dict(sorted(reader.ranges.items(), key=lambda item: int(item[0].split("-", 1)[0]))),
            "globalDigestVerified": False,
            "format": "little-endian DAF/SPK type 2",
            "time": "TDB",
            "frame": "ICRF",
            "state": "Moon (301) minus Earth (399), both relative to Earth-Moon barycenter (3); geometric",
        },
        "acceptedRange": {"ttDaysFromJ2000Inclusive": [-ACCEPTED_TT_DAYS, ACCEPTED_TT_DAYS], "tdbMarginDays": TDB_TT_MARGIN_DAYS},
        "directCandidate": {
            "segments": layout,
            "recordDays": 4.0,
            "coefficientsPerAxis": 13,
            "recordCount": record_count,
            "coefficientCount": coefficient_count,
            "float64Bytes": coefficient_count * 8,
            "float32Bytes": coefficient_count * 4,
            "derivative": "analytic derivative of the same 13 Chebyshev coefficients; no additional table",
        },
        "independentReference": {
            "archive": str(REFERENCE.relative_to(ROOT)),
            "sampleCount": len(vectors),
            "selection": "the complete archived set: 19 long-span dates from 2002 BCE through 6000 CE and 11 dates at the existing DE440 transition regions",
            "maximumPositionDifferenceKm": maximum_position_km,
            "maximumVelocityDifferenceKmPerSecond": maximum_velocity_km_per_second,
            "records": records,
        },
        "float32Sample": {
            "sampleCount": len(vectors),
            "maximumCoefficientRoundingPositionComponentBoundAU": maximum_float32_position_component_au,
            "maximumCoefficientRoundingRateComponentBoundAUPerDay": maximum_float32_rate_component_au_per_day,
            "maximumAngularBoundArcminutesUsingSmallestSampledRange": sampled_angular_bound_arcminutes,
            "fullRangeScanned": False,
        },
        "runtimeSample": {
            "language": "Python 3",
            "evaluator": "three 13-term Chebyshev position and analytic-rate evaluations over sampled Float32 coefficients",
            "iterations": iterations,
            "seconds": elapsed,
            "evaluationsPerSecond": iterations / elapsed,
            "checksum": checksum,
            "productionRepresentative": False,
        },
        "assessment": {
            "fullRangeQualified": False,
            "finding": "Direct storage adds 217.36 MiB as Float64 or 108.68 MiB as Float32 before source encoding. The 30-record Float32 check is sparse and cannot establish the accepted-range accuracy contract.",
            "nextStep": "Fit and fully qualify a compact DE441-derived representation against every source record, then compare its measured size and production runtime with the direct candidate before choosing the shipping model.",
        },
    }


def encoded(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=SOURCE_URL, help="official URL or a local DE441 kernel")
    parser.add_argument("--check", action="store_true", help="regenerate the evidence and require an exact match except runtime observations")
    args = parser.parse_args()
    evidence = build_evidence(args.source)
    if args.check:
        saved = json.loads(OUTPUT.read_bytes())
        for value in (saved, evidence):
            value["runtimeSample"].pop("seconds", None)
            value["runtimeSample"].pop("evaluationsPerSecond", None)
        if saved != evidence:
            raise SystemExit("DE441 direct-candidate evidence differs")
        print("Verified DE441 direct-candidate evidence")
    else:
        OUTPUT.write_bytes(encoded(evidence))
        print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
