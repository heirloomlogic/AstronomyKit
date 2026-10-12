#!/usr/bin/env python3
"""Generate binary64 DE-backed planet components for issue 248."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import shutil
import struct
import tempfile
from typing import NamedTuple
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Sources/AstronomyKit/Engine/Planets/Generated/DE441"
MANIFEST = ROOT / "Scripts/planet-data/de441-foundation.json"
FIXTURES = ROOT / "Scripts/planet-data/de441-direct-fixtures.json"
START_JD_TDB = 2_414_988.5 - 2.2e-8
END_JD_TDB = 2_499_423.5 + 2.2e-8
J2000 = 2_451_545.0
BATCH_RECORDS = 8_192

SPEC = importlib.util.spec_from_file_location("spk_direct", ROOT / "Scripts/assess-moon-de441.py")
spk = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(spk)


class Source(NamedTuple):
    url: str
    identity: tuple


class Component(NamedTuple):
    source: str
    target: int
    center: int


SOURCES = {
    "de441": Source(spk.SOURCE_URL, (spk.SOURCE_BYTES, spk.SOURCE_ETAG, spk.SOURCE_LAST_MODIFIED)),
    "jup365": Source(
        "https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/jup365.bsp",
        (1_136_581_632, None, "Sun, 14 Mar 2021 15:29:22 GMT"),
    ),
    "ura184_part-3": Source(
        "https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/ura184_part-3.bsp",
        (386_885_632, None, "Fri, 26 Sep 2025 13:43:01 GMT"),
    ),
    "nep098_part-1": Source(
        "https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/nep098_part-1.bsp",
        (821_838_848, None, "Mon, 13 Jul 2026 17:57:46 GMT"),
    ),
}

COMPONENTS = {
    "mercuryBarycenter": Component("de441", 1, 0),
    "venusBarycenter": Component("de441", 2, 0),
    "earthBarycenter": Component("de441", 3, 0),
    "earthOffset": Component("de441", 399, 3),
    "marsBarycenter": Component("de441", 4, 0),
    "jupiterBarycenter": Component("de441", 5, 0),
    "jupiterOffset": Component("jup365", 599, 5),
    "uranusBarycenter": Component("ura184_part-3", 7, 0),
    "uranusOffset": Component("ura184_part-3", 799, 7),
    "neptuneBarycenter": Component("de441", 8, 0),
    "neptuneOffset": Component("nep098_part-1", 899, 8),
    "sun": Component("de441", 10, 0),
}


def source_bindings():
    return ["Scripts/generate-planet-de441.py", "Scripts/assess-moon-de441.py"]


def output_name(name):
    return f"PlanetDE441{name[0].upper()}{name[1:]}Data.swift"


def output_names():
    return {output_name(name) for name in COMPONENTS if name != "sun"}


def output_paths():
    return {OUTPUT / name for name in output_names()}


class CachedReader:
    def __init__(self, name, directory, expected=None):
        self.name = name
        self.source = SOURCES[name]
        self.directory = Path(directory) / name
        self.directory.mkdir(parents=True, exist_ok=True)
        self.expected = expected or {}
        self.ranges = {}

    def read(self, start, count):
        if start < 0 or count <= 0:
            raise ValueError("invalid byte range")
        key = f"{start}-{start + count - 1}"
        path = self.directory / f"{key}.bin"
        receipt = path.with_suffix(".json")
        if path.exists():
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            if key in self.expected:
                if digest != self.expected[key]:
                    raise ValueError(f"cached source digest differs: {self.name} {key}")
            elif not receipt.exists() or json.loads(receipt.read_text()) != {
                "sha256": digest,
                "identity": list(self.source.identity),
            }:
                raise ValueError(f"cached source receipt differs: {self.name} {key}")
        else:
            end = start + count - 1
            request = urllib.request.Request(self.source.url, headers={"Range": f"bytes={start}-{end}"})
            with urllib.request.urlopen(request) as response:
                data = response.read()
                identity = (
                    int(response.headers["Content-Range"].split("/")[-1]),
                    response.headers.get("ETag"),
                    response.headers.get("Last-Modified"),
                )
            if identity != self.source.identity:
                raise ValueError(f"official source identity changed: {self.name}")
            digest = hashlib.sha256(data).hexdigest()
            if key in self.expected and digest != self.expected[key]:
                raise ValueError(f"downloaded source digest differs: {self.name} {key}")
            path.write_bytes(data)
            receipt.write_text(json.dumps({"sha256": digest, "identity": list(self.source.identity)}))
        if len(data) != count:
            raise ValueError(f"short source range: {self.name} {key}")
        self.ranges[key] = digest
        return data


def layouts(reader, component):
    segments = spk.read_segments(reader)
    selected = []
    for segment in segments:
        if (segment.target, segment.center) != (component.target, component.center):
            continue
        metadata = spk.read_metadata(reader, segment)
        if (segment.frame, segment.kind) != (1, 2):
            raise ValueError("component is not type-2 ICRF")
        selected.append((segment, metadata))
    selected.sort(key=lambda pair: pair[0].start_seconds_tdb)
    result = []
    cursor = START_JD_TDB
    for segment, metadata in selected:
        low = J2000 + segment.start_seconds_tdb / spk.SECONDS_PER_DAY
        high = J2000 + segment.end_seconds_tdb / spk.SECONDS_PER_DAY
        if high <= cursor or low >= END_JD_TDB:
            continue
        if low > cursor:
            raise ValueError("source coverage gap")
        stop = min(high, END_JD_TDB)
        first, count = spk.record_window(metadata, cursor, stop)
        result.append((segment, metadata, first, count))
        cursor = stop
    if cursor != END_JD_TDB or not result:
        raise ValueError("source coverage is incomplete")
    days = result[0][1].record_days
    words = result[0][1].record_words
    if any(metadata.record_days != days or metadata.record_words != words for _, metadata, _, _ in result):
        raise ValueError("component record shape changes inside the selected window")
    return result


def evaluate(axes, x, days):
    values = [spk.chebyshev_value_and_rate(axis, x, days) for axis in axes]
    return tuple(value for value, _ in values), tuple(rate for _, rate in values)


def validate_payload(data, record_count, coefficient_count):
    expected = record_count * 3 * coefficient_count * 8
    if len(data) != expected:
        raise ValueError("binary64 component length differs")
    if any(not math.isfinite(value[0]) for value in struct.iter_unpack("<d", data)):
        raise ValueError("binary64 component contains a nonfinite coefficient")


def load_component(reader, component):
    layout = layouts(reader, component)
    jobs = []
    for segment, metadata, first, count in layout:
        for offset in range(0, count, BATCH_RECORDS):
            index = first + offset
            size = min(BATCH_RECORDS, count - offset)
            jobs.append((segment, metadata, index, size))

    def read(job):
        segment, metadata, first, count = job
        start = (segment.first_word - 1 + first * metadata.record_words) * 8
        return job, reader.read(start, count * metadata.record_words * 8)

    records = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for (segment, metadata, first, count), raw in pool.map(read, jobs):
            coefficient_count = (metadata.record_words - 2) // 3
            if coefficient_count * 3 + 2 != metadata.record_words:
                raise ValueError("invalid type-2 coefficient count")
            for offset in range(count):
                values = struct.unpack_from(
                    f"<{metadata.record_words}d", raw, offset * metadata.record_words * 8)
                start = metadata.start_jd_tdb + (first + offset) * metadata.record_days
                expected = ((start - J2000 + metadata.record_days / 2) * spk.SECONDS_PER_DAY, metadata.record_days * spk.SECONDS_PER_DAY / 2)
                if values[:2] != expected or not all(math.isfinite(value) for value in values):
                    raise ValueError("source record midpoint, radius or finite domain differs")
                if records and start != records[-1][0] + records[-1][1]:
                    raise ValueError("source record grid is not contiguous")
                axes = tuple(
                    tuple(values[2 + axis * coefficient_count : 2 + (axis + 1) * coefficient_count])
                    for axis in range(3)
                )
                records.append((start, metadata.record_days, axes))
    if not records:
        raise ValueError("component has no selected records")
    return records


def payload(records):
    data = b"".join(struct.pack(f"<{len(axis)}d", *axis) for _, _, axes in records for axis in axes)
    validate_payload(data, len(records), len(records[0][2][0]))
    return data


def fixtures(name, records):
    indices = sorted({0, len(records) // 2, len(records) - 1})
    rows = []
    for index in indices:
        start, days, axes = records[index]
        for x in (-1.0, 0.0, 1.0):
            position, velocity = evaluate(axes, x, days)
            rows.append(
                {
                    "component": name,
                    "record": index,
                    "x": x,
                    "startJDTDB": start,
                    "positionKm": position,
                    "velocityKmPerTDBDay": velocity,
                }
            )
    return rows


def render(name, data, records):
    record_bytes = len(records[0][2][0]) * 3 * 8
    lines = "\n".join(
        base64.b64encode(data[index : index + record_bytes]).decode("ascii")
        for index in range(0, len(data), record_bytes)
    )
    start, days, axes = records[0]
    return f'''// Generated by Scripts/generate-planet-de441.py; do not edit.
// Source identities and byte-range SHA-256 values: Scripts/planet-data/de441-foundation.json.
// swift-format-ignore-file

extension Engine.PlanetDE441 {{
    static var {name}: Engine.DirectChebyshevTable {{ {name}Table }}
    private static let {name}Table = Engine.DirectChebyshevTable(
        start: {start - J2000!r}, days: {days!r}, recordCount: {len(records)},
        coefficientCount: {len(axes[0])}, recordsPerChunk: {len(records)},
        chunks: [{name}Payload]
    )
    private static var {name}Payload: StaticString {{
        @inline(never) get {{
            """
{lines}
"""
        }}
    }}
}}
'''


def sorted_ranges(ranges):
    return dict(sorted(ranges.items(), key=lambda item: int(item[0].split("-", 1)[0])))


def build(cache):
    prior = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    readers = {
        name: CachedReader(
            name,
            cache,
            prior.get("sources", {}).get(name, {}).get("retrievedByteRangesSHA256"),
        )
        for name in SOURCES
    }
    rendered = {}
    rows = []
    reports = {}
    for name, component in COMPONENTS.items():
        print(f"Loading {name} from {component.source}", flush=True)
        records = load_component(readers[component.source], component)
        data = payload(records)
        rows.extend(fixtures(name, records))
        reports[name] = {
            "source": component.source,
            "target": component.target,
            "center": component.center,
            "frame": "ICRF",
            "clock": "TDB",
            "startJDTDB": records[0][0],
            "exclusiveEndJDTDB": records[-1][0] + records[-1][1],
            "recordDays": records[0][1],
            "recordCount": len(records),
            "coefficientCount": len(records[0][2][0]),
            "encodedBytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
        if name != "sun":
            rendered[output_name(name)] = render(name, data, records)
    manifest = {
        "schemaVersion": 1,
        "generatorBindings": {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in source_bindings()},
        "requestedJDTDB": [START_JD_TDB, END_JD_TDB],
        "composition": "Binary64 type-2 SPK components in source kilometres on ICRF axes. Runtime composition subtracts the DE441 Sun. Earth, Jupiter, Uranus and Neptune add their physical-center offsets. Uranus alone uses the DE442 barycenter embedded in URA184, with the DE441 Sun.",
        "components": reports,
        "sources": {
            name: {
                "url": source.url,
                "identity": list(source.identity),
                "wholeKernelSHA256": None,
                "retrievedByteRangesSHA256": sorted_ranges(readers[name].ranges),
            }
            for name, source in SOURCES.items()
        },
        "generatedBytes": sum(row["encodedBytes"] for name, row in reports.items() if name != "sun"),
    }
    return rendered, manifest, {"schemaVersion": 1, "selection": "First, middle and last source record at x=-1, 0 and 1 for every component.", "rows": rows}


def verify_embedded(manifest, fixture):
    if manifest.get("schemaVersion") != 1 or set(manifest.get("components", {})) != set(COMPONENTS):
        raise ValueError("planet foundation manifest inventory differs")
    if manifest.get("generatorBindings") != {
        path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in source_bindings()
    }:
        raise ValueError("planet foundation generator binding differs")
    if {path.name for path in output_paths()} != output_names() or set(OUTPUT.glob("*.swift")) != output_paths():
        raise ValueError("generated planet foundation file set differs")
    for name, report in manifest["components"].items():
        if name == "sun":
            continue
        path = OUTPUT / output_name(name)
        try:
            data = base64.b64decode(path.read_text().split('"""', 2)[1], validate=False)
        except (IndexError, ValueError) as error:
            raise ValueError(f"invalid generated payload: {name}") from error
        validate_payload(data, report["recordCount"], report["coefficientCount"])
        if len(data) != report["encodedBytes"] or hashlib.sha256(data).hexdigest() != report["sha256"]:
            raise ValueError(f"generated payload digest differs: {name}")
    rows = fixture.get("rows", [])
    if fixture.get("schemaVersion") != 1 or len(rows) != len(COMPONENTS) * 9:
        raise ValueError("direct fixture inventory differs")
    if {row["component"] for row in rows} != set(COMPONENTS):
        raise ValueError("direct fixture component inventory differs")


def publish(rendered, manifest, fixture):
    with tempfile.TemporaryDirectory(prefix="planet-de441-") as directory:
        stage = Path(directory)
        for name, source in rendered.items():
            (stage / name).write_text(source)
        verify_names = {path.name for path in stage.glob("*.swift")}
        if verify_names != output_names():
            raise ValueError("staged generated file set differs")
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for path in stage.iterdir():
            target = OUTPUT / path.name
            if not target.exists() or target.read_bytes() != path.read_bytes():
                shutil.copyfile(path, target)
        for path in set(OUTPUT.glob("*.swift")) - output_paths():
            path.unlink()
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    FIXTURES.write_text(json.dumps(fixture, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--verify-source", action="store_true")
    parser.add_argument("--cache", type=Path, default=ROOT / ".context/issue-248/ranges")
    args = parser.parse_args()
    if args.check:
        verify_embedded(json.loads(MANIFEST.read_text()), json.loads(FIXTURES.read_text()))
        print("Verified embedded DE-backed planet foundation")
        return
    rendered, manifest, fixture = build(args.cache)
    if args.verify_source:
        manifest = json.loads(json.dumps(manifest))
        fixture = json.loads(json.dumps(fixture))
        current_manifest = json.loads(MANIFEST.read_text())
        current_fixture = json.loads(FIXTURES.read_text())
        if manifest != current_manifest or fixture != current_fixture:
            raise SystemExit("official source replay differs from the committed foundation")
        verify_embedded(current_manifest, current_fixture)
        print("Verified official source replay for the DE-backed planet foundation")
        return
    publish(rendered, manifest, fixture)
    verify_embedded(manifest, fixture)
    print("Wrote DE-backed planet foundation")


if __name__ == "__main__":
    main()
