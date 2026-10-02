#!/usr/bin/env python3
"""Generate complete model tables from pinned, checksum-verified upstream data.

No network or third-party Python packages are required. Consumers use the
committed headers; --check verifies regeneration leaves them unchanged.
"""
import argparse
import array
from dataclasses import dataclass
import gzip
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Scripts/model-data"
OUTPUT = ROOT / "Sources/CLibAstronomy/generated"
SWIFT_OUTPUT = ROOT / "Sources"
POLYNOMIAL_DATA = ROOT / "Scripts/performance/polynomial/data"
SWIFT_MANIFEST = DATA / "swift-prototype-manifest.json"
BODIES = dict(zip(("mer", "ven", "ear", "mar", "jup", "sat", "ura", "nep"),
                  ("Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune")))
POLYNOMIAL_START, POLYNOMIAL_STOP = -36524.5, 36889.5
SWIFT_CHUNK_SIZE = 16_384


@dataclass(frozen=True)
class PolynomialBody:
    name: str
    coefficient_bits: tuple[int, ...]
    validity: bytes
    coefficient_sha256: str
    validity_sha256: str
    degree: int
    width: int
    segments: int


@dataclass(frozen=True)
class VSOPSeries:
    body: int
    coordinate: int
    power: int
    offset: int
    count: int


@dataclass(frozen=True)
class SwiftModel:
    polynomials: tuple[PolynomialBody, ...]
    vsop_terms: tuple[tuple[int, int, int], ...]
    vsop_series: tuple[VSOPSeries, ...]
    nutation_rows: tuple[tuple[tuple[int, ...], tuple[int, ...]], ...]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def double_bits(text):
    return struct.unpack("<Q", struct.pack("<d", float(text)))[0]


def swift_input_manifest():
    paths = []
    for directory in (DATA, POLYNOMIAL_DATA):
        paths.extend(path for path in directory.rglob("*") if path.is_file() and path != SWIFT_MANIFEST)
    return {path.relative_to(ROOT).as_posix(): sha256(path) for path in sorted(paths)}


def load_polynomials():
    rows = json.loads((POLYNOMIAL_DATA / "generation.json").read_text())["bodies"]
    expected_names = tuple(BODIES.values())
    if tuple(row["body"] for row in rows) != expected_names:
        raise ValueError("Incomplete polynomial body manifest")
    qualification = json.loads((POLYNOMIAL_DATA / "shipping-validity.json").read_text())
    integration = json.loads((POLYNOMIAL_DATA / "integration-validity.json").read_text())
    result = []
    for row in rows:
        name = row["body"]
        raw = gzip.decompress((POLYNOMIAL_DATA / f"{name}.bin.gz").read_bytes())
        validity = (POLYNOMIAL_DATA / f"{name}.valid").read_bytes()
        if hashlib.sha256(raw).hexdigest() != row["coefficientSHA256"]:
            raise ValueError(f"{name}: coefficient hash mismatch")
        if hashlib.sha256(validity).hexdigest() != row["validitySHA256"]:
            raise ValueError(f"{name}: validity hash mismatch")
        degree, width, segments = row["degree"], row["width"], row["segments"]
        if degree != 12 or width not in (8, 16, 32) or segments != math.ceil((POLYNOMIAL_STOP - POLYNOMIAL_START) / width):
            raise ValueError(f"{name}: unsupported polynomial grid")
        if len(raw) != segments * 3 * (degree + 1) * 8 or len(validity) != segments or not set(validity) <= {0, 1}:
            raise ValueError(f"{name}: invalid polynomial archive size")
        exclusions = qualification["invalid"][name] + integration["invalid"][name]
        if any(type(index) is not int or not 0 <= index < segments for index in exclusions):
            raise ValueError(f"{name}: invalid exclusion index")
        excluded = set(exclusions)
        validity = bytes(0 if index in excluded else value for index, value in enumerate(validity))
        coefficients = array.array("Q")
        coefficients.frombytes(raw)
        if sys.byteorder != "little":
            coefficients.byteswap()
        if not all(math.isfinite(struct.unpack("<d", value.to_bytes(8, "little"))[0]) for value in coefficients):
            raise ValueError(f"{name}: nonfinite polynomial coefficient")
        result.append(PolynomialBody(name, tuple(coefficients), validity, row["coefficientSHA256"], hashlib.sha256(validity).hexdigest(), degree, width, segments))
    return tuple(result)


def load_vsop():
    manifest = json.loads((DATA / "manifest.json").read_text())
    terms = []
    series = []
    for body_index, (suffix, _) in enumerate(BODIES.items()):
        path = DATA / f"VSOP87B.{suffix}"
        if sha256(path) != manifest["files"][path.name]["sha256"]:
            raise ValueError(f"Source checksum mismatch: {path.name}")
        lines = iter(path.read_text().splitlines())
        powers = {1: 0, 2: 0, 3: 0}
        for header in lines:
            match = re.search(r"VARIABLE\s+(\d).*\*T\*\*(\d)\s+(\d+) TERMS", header)
            if not match:
                raise ValueError(f"Invalid VSOP header: {header}")
            coordinate, power, count = map(int, match.groups())
            if coordinate not in powers or power != powers[coordinate] or count <= 0:
                raise ValueError("Missing or reordered VSOP series")
            powers[coordinate] += 1
            offset = len(terms)
            for index in range(count):
                row = next(lines)
                if int(row[5:10]) != index + 1:
                    raise ValueError("Missing or reordered VSOP term")
                values = row.split()[-3:]
                if len(values) != 3:
                    raise ValueError("Invalid VSOP coefficient row")
                terms.append(tuple(double_bits(value) for value in values))
            series.append(VSOPSeries(body_index, coordinate - 1, power, offset, count))
    return tuple(terms), tuple(series)


def load_nutation():
    manifest = json.loads((DATA / "manifest.json").read_text())
    path = DATA / "iau2000b.txt"
    if sha256(path) != manifest["files"][path.name]["sha256"]:
        raise ValueError("Source checksum mismatch: iau2000b.txt")
    rows = path.read_text().splitlines()
    if len(rows) != 77:
        raise ValueError("IAU2000B must contain exactly 77 terms")
    result = []
    for row in rows:
        values = row.split()
        if len(values) != 11:
            raise ValueError("Invalid nutation coefficient row")
        result.append((tuple(map(int, values[:5])), tuple(double_bits(value) for value in values[5:])))
    return tuple(result)


def load_swift_model():
    terms, series = load_vsop()
    return SwiftModel(load_polynomials(), terms, series, load_nutation())


def render_bits(name, values, visibility="internal"):
    lines = [f"{visibility} let {name}: [UInt64] = ["]
    for offset in range(0, len(values), 8):
        lines.append("    " + ", ".join(f"0x{value:016x}" for value in values[offset:offset + 8]) + ",")
    lines.append("]")
    return "\n".join(lines) + "\n"


def render_swift_model():
    model = load_swift_model()
    notice = "// Generated by Scripts/generate-models.py --swift-prototype. Do not edit.\n\n"
    files = {}
    for body in model.polynomials:
        chunks = []
        target = f"AstronomyPolynomial{body.name}Prototype"
        for number, start in enumerate(range(0, len(body.coefficient_bits), SWIFT_CHUNK_SIZE)):
            symbol = f"polynomial{body.name}Bits{number}"
            relative = f"{target}/Generated/Polynomial{body.name}{number}.swift"
            files[relative] = notice + render_bits(symbol, body.coefficient_bits[start:start + SWIFT_CHUNK_SIZE])
            chunks.append((symbol, start, min(start + SWIFT_CHUNK_SIZE, len(body.coefficient_bits))))
        access = [notice, f"public let polynomial{body.name}Validity: [UInt8] = [", "    " + ", ".join(map(str, body.validity)), "]", "", f"public func polynomial{body.name}BitPattern(at index: Int) -> UInt64? {{", f"    guard index >= 0 && index < {len(body.coefficient_bits)} else {{ return nil }}", f"    switch index / {SWIFT_CHUNK_SIZE} {{"]
        for chunk_number, (symbol, start, _) in enumerate(chunks):
            access.append(f"    case {chunk_number}: return {symbol}[index - {start}]")
        access.extend(["    default: return nil", "    }", "}", ""])
        files[f"{target}/Generated/Access.swift"] = "\n".join(access)

    flattened_terms = tuple(value for term in model.vsop_terms for value in term)
    vsop = [notice, render_bits("vsopTermBits", flattened_terms, "public"), "public struct GeneratedVSOPSeries: Sendable {", "    public let body: Int", "    public let coordinate: Int", "    public let power: Int", "    public let offset: Int", "    public let count: Int", "}", "", "public let generatedVSOPSeries: [GeneratedVSOPSeries] = ["]
    for row in model.vsop_series:
        vsop.append(f"    GeneratedVSOPSeries(body: {row.body}, coordinate: {row.coordinate}, power: {row.power}, offset: {row.offset}, count: {row.count}),")
    vsop.extend(["]", ""])
    files["AstronomyVSOPPrototype/Generated/VSOPTerms.swift"] = "\n".join(vsop)
    nutation_integer = tuple(value & 0xffffffffffffffff for row in model.nutation_rows for value in row[0])
    nutation_bits = tuple(value for row in model.nutation_rows for value in row[1])
    files["AstronomyNutationPrototype/Generated/Nutation.swift"] = notice + render_bits("nutationIntegerBits", nutation_integer, "public") + "\n" + render_bits("nutationCoefficientBits", nutation_bits, "public")

    metadata = [
        notice,
        "public struct GeneratedPolynomialMetadata: Sendable {",
        "    public let name: String",
        "    public let startTT: Double",
        "    public let stopTT: Double",
        "    public let degree: Int",
        "    public let width: Int",
        "    public let segments: Int",
        "    public let coefficientCount: Int",
        "    public let coefficientSHA256: String",
        "    public let validitySHA256: String",
        "}",
        "",
        "public let generatedPolynomialMetadata: [GeneratedPolynomialMetadata] = [",
    ]
    for body in model.polynomials:
        metadata.append(f"    GeneratedPolynomialMetadata(name: \"{body.name}\", startTT: Double(bitPattern: 0x{double_bits(str(POLYNOMIAL_START)):016x}), stopTT: Double(bitPattern: 0x{double_bits(str(POLYNOMIAL_STOP)):016x}), degree: {body.degree}, width: {body.width}, segments: {body.segments}, coefficientCount: {len(body.coefficient_bits)}, coefficientSHA256: \"{body.coefficient_sha256}\", validitySHA256: \"{body.validity_sha256}\"),")
    metadata.extend(["]", ""])
    files["AstronomyModelPrototypeGenerated/Generated/Metadata.swift"] = "\n".join(metadata)
    return files


def swift_output_manifest(outputs):
    model = load_swift_model()
    return {
        "schemaVersion": 1,
        "inputs": swift_input_manifest(),
        "outputs": {name: hashlib.sha256(content.encode()).hexdigest() for name, content in sorted(outputs.items())},
        "counts": {
            "polynomialCoefficients": sum(len(body.coefficient_bits) for body in model.polynomials),
            "disabledPolynomialSegments": sum(value == 0 for body in model.polynomials for value in body.validity),
            "vsopTerms": len(model.vsop_terms),
            "vsopSeries": len(model.vsop_series),
            "nutationRows": len(model.nutation_rows),
        },
        "chunkSize": SWIFT_CHUNK_SIZE,
    }


def write_swift_model(check):
    outputs = render_swift_model()
    manifest = json.dumps(swift_output_manifest(outputs), indent=2, sort_keys=True) + "\n"
    actual = {path.relative_to(SWIFT_OUTPUT).as_posix() for path in SWIFT_OUTPUT.glob("Astronomy*Prototype*/Generated/*.swift")}
    expected = set(outputs)
    if check:
        for name, content in outputs.items():
            path = SWIFT_OUTPUT / name
            if not path.exists() or path.read_text() != content:
                raise SystemExit(f"Generated Swift model differs: {path}")
        if not SWIFT_MANIFEST.exists() or SWIFT_MANIFEST.read_text() != manifest:
            raise SystemExit(f"Generated Swift model differs: {SWIFT_MANIFEST}")
        if actual != expected:
            raise SystemExit(f"Generated Swift model file set differs: expected {sorted(expected)}, found {sorted(actual)}")
        print("Verified complete Swift model prototype")
        return
    for stale in actual - expected:
        (SWIFT_OUTPUT / stale).unlink()
    for name, content in outputs.items():
        path = SWIFT_OUTPUT / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    SWIFT_MANIFEST.write_text(manifest)
    print("Generated complete Swift model prototype")


def generate():
    manifest = json.loads((DATA / "manifest.json").read_text())
    for name, record in manifest["files"].items():
        if hashlib.sha256((DATA / name).read_bytes()).hexdigest() != record["sha256"]:
            raise ValueError(f"Source checksum mismatch: {name}")
    notice = ("/* Generated by Scripts/generate-models.py; do not edit.\n"
              f" * Astronomy Engine source revision {manifest['upstreamRevision']}.\n"
              " * See Scripts/model-data/manifest.json and THIRD_PARTY_NOTICES. */\n")
    output = [notice, """typedef struct
{
    double amplitude;
    double phase;
    double frequency;
}
vsop_term_t;

typedef struct
{
    int nterms;
    const vsop_term_t *term;
}
vsop_series_t;

"""]
    for suffix, body in BODIES.items():
        lines = iter((DATA / f"VSOP87B.{suffix}").read_text().splitlines())
        counts = {1: [], 2: [], 3: []}
        for header in lines:
            match = re.search(r"VARIABLE\s+(\d).*\*T\*\*(\d)\s+(\d+) TERMS", header)
            if not match:
                raise ValueError(f"Invalid VSOP header: {header}")
            coordinate, power, count = map(int, match.groups())
            if power != len(counts[coordinate]) or count <= 0:
                raise ValueError("Missing or reordered VSOP series")
            counts[coordinate].append(count)
            name = f"vsop_{('lon', 'lat', 'rad')[coordinate-1]}_{body}_{power}"
            output.append(f"static const vsop_term_t {name}[] = {{\n")
            for index in range(count):
                row = next(lines)
                if int(row[5:10]) != index + 1:
                    raise ValueError("Missing or reordered VSOP term")
                # Preserve the full decimal source coefficients, without float formatting.
                terms = row.split()[-3:]
                if len(terms) != 3:
                    raise ValueError("Invalid VSOP coefficient row")
                output.append("    { " + ", ".join(terms) + " },\n")
            output.append("};\n")
        for coordinate, sizes in counts.items():
            name = f"vsop_{('lon', 'lat', 'rad')[coordinate-1]}_{body}"
            output.append(f"static const vsop_series_t {name}[] = {{\n")
            output.extend(f"    {{ {count}, {name}_{power} }},\n" for power, count in enumerate(sizes))
            output.append("};\n")
    nutation = [notice, "static const struct { int n[5]; double c[6]; } iau2000b_terms[] = {\n"]
    rows = (DATA / "iau2000b.txt").read_text().splitlines()
    if len(rows) != 77:
        raise ValueError("IAU2000B must contain exactly 77 terms")
    for row in rows:
        values = row.split()
        if len(values) != 11:
            raise ValueError("Invalid nutation coefficient row")
        nutation.append("    { { " + ", ".join(values[:5]) + " }, { " + ", ".join(values[5:]) + " } },\n")
    nutation.append("};\n")
    return {"vsop87b_full.h": "".join(output), "iau2000b_full.h": "".join(nutation)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--swift-prototype", action="store_true")
    parser.add_argument("--check-swift-prototype", action="store_true")
    args = parser.parse_args()
    if args.swift_prototype or args.check_swift_prototype:
        write_swift_model(args.check_swift_prototype)
        raise SystemExit
    for name, content in generate().items():
        path = OUTPUT / name
        if args.check:
            if not path.exists() or path.read_text() != content:
                raise SystemExit(f"Generated model differs: {path}")
        else:
            path.write_text(content)
        print(f"Verified {name}" if args.check else f"Generated {name}")
