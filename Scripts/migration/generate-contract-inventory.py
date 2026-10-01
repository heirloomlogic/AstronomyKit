#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlparse


BASELINE_REVISION = "cdb533dbe85c76b39a958ca92f9155d8bd55b392"
OUTPUT = Path("Documentation/Migration/contract-inventory.json")

SOURCE_ISSUES = {
    "Apsis.swift": 92,
    "AstronomyError.swift": 84,
    "AstronomyKit.swift": 96,
    "Atmosphere.swift": 86,
    "CelestialBody.swift": 84,
    "Chiron.swift": 88,
    "CivilTime.swift": 84,
    "Constellation.swift": 91,
    "Coordinates.swift": 86,
    "Eclipse.swift": 93,
    "Elongation.swift": 92,
    "FixedStar.swift": 91,
    "GravitySimulation.swift": 88,
    "Illumination.swift": 89,
    "JupiterMoons.swift": 90,
    "LagrangePoint.swift": 90,
    "Libration.swift": 87,
    "LunarNode.swift": 92,
    "MoonPhase.swift": 92,
    "Observer.swift": 86,
    "Position.swift": 89,
    "RelativeLongitude.swift": 92,
    "RiseSet.swift": 92,
    "Rotation.swift": 86,
    "RotationAxis.swift": 90,
    "Search.swift": 84,
    "Seasons.swift": 92,
    "SolarAltitudeObservation.swift": 94,
    "Time.swift": 84,
    "Transit.swift": 93,
}

TEST_ISSUES = {
    "AcceptedTimeRangeTests.swift": 97,
    "AltitudeSearchTests.swift": 92,
    "ApsisTests.swift": 92,
    "AstroTimeTests.swift": 84,
    "AstronomyErrorTests.swift": 84,
    "AtmosphereTests.swift": 86,
    "AuditValidationTests.swift": 81,
    "CelestialBodyTests.swift": 84,
    "ChironTests.swift": 88,
    "CivilTimeTests.swift": 84,
    "ConstellationTests.swift": 91,
    "ConstellationThreadSafetyTests.swift": 95,
    "CoordinatesTests.swift": 86,
    "DeltaTModelCaptureTests.swift": 84,
    "DeltaTThreadSafetyTests.swift": 95,
    "EclipseTests.swift": 93,
    "EclipticStateTests.swift": 89,
    "ElongationTests.swift": 92,
    "FixedStarConcurrencyTests.swift": 95,
    "FixedStarTests.swift": 91,
    "GravitySimulationTests.swift": 88,
    "HugeTimeTests.swift": 97,
    "IlluminationTests.swift": 89,
    "JPLValidationTests.swift": 81,
    "JupiterMoonsTests.swift": 90,
    "LagrangePointTests.swift": 90,
    "LibrationTests.swift": 87,
    "LightTravelTests.swift": 89,
    "LocalSolarEclipseTests.swift": 93,
    "LunarNodeTests.swift": 92,
    "MoonCacheTests.swift": 95,
    "MoonTests.swift": 87,
    "NutationCacheTests.swift": 95,
    "ObserverTests.swift": 86,
    "ObserverVectorTests.swift": 86,
    "PlutoRangeTests.swift": 88,
    "PlutoThreadSafetyTests.swift": 95,
    "PolynomialTests.swift": 85,
    "PositionTests.swift": 89,
    "RelativeLongitudeTests.swift": 92,
    "ReproducibilityTests.swift": 80,
    "RiseSetTests.swift": 92,
    "RotationAxisTests.swift": 90,
    "RotationTests.swift": 86,
    "SearchTests.swift": 84,
    "SeasonsTests.swift": 92,
    "SolarAltitudeObservationTests.swift": 94,
    "StateVectorExtensionTests.swift": 89,
    "TransitTests.swift": 93,
    "VsopCacheTests.swift": 95,
}

PATCH_ISSUES = {
    1: 95,
    2: 95,
    3: 95,
    4: 95,
    5: 88,
    6: 97,
    7: 85,
    8: 95,
    9: 85,
    10: 84,
    11: 85,
    12: 89,
    13: 95,
    14: 95,
    15: 97,
    16: 97,
    17: 97,
    18: 84,
}

GENERATED_ISSUES = {
    "Sources/AstronomyKit/SolarAltitudeBounds.swift": 94,
    "Sources/AstronomyKit/UTCOffsetTable.swift": 84,
    "Sources/CLibAstronomy/generated/iau2000b_full.h": 86,
    "Sources/CLibAstronomy/generated/polynomial-data.h": 85,
    "Sources/CLibAstronomy/generated/vsop87b_full.h": 85,
}

GENERATORS = {
    "Sources/AstronomyKit/SolarAltitudeBounds.swift": "Scripts/numerics/solar-altitude/bounds.py",
    "Sources/AstronomyKit/UTCOffsetTable.swift": "Scripts/generate-time-table.py",
    "Sources/CLibAstronomy/generated/iau2000b_full.h": "Scripts/generate-models.py",
    "Sources/CLibAstronomy/generated/polynomial-data.h": "Scripts/performance/polynomial/embed.py",
    "Sources/CLibAstronomy/generated/vsop87b_full.h": "Scripts/generate-models.py",
}

CROSS_CUTTING_CONTRACTS = [
    {
        "id": "errors",
        "migrationIssue": 97,
        "obligation": "Preserve AstronomyError cases, C status translation, throwing boundaries, and the distinction between invalid input, bad time, unsupported body, and convergence failure.",
        "evidence": ["Sources/AstronomyKit/AstronomyError.swift", "Tests/AstronomyKitTests/AstronomyErrorTests.swift", "Tests/AstronomyKitTests/HugeTimeTests.swift"],
    },
    {
        "id": "nil-results",
        "migrationIssue": 96,
        "obligation": "Preserve every optional return and the exact conditions that produce nil instead of a value or thrown error.",
        "evidence": ["Sources/AstronomyKit", "Tests/AstronomyKitTests"],
    },
    {
        "id": "serialization",
        "migrationIssue": 96,
        "obligation": "Preserve Codable conformance, encoded field names and values, and AstroTime decoding validation.",
        "evidence": ["Sources/AstronomyKit/Time.swift", "Tests/AstronomyKitTests/AstroTimeTests.swift", "Sources/AstronomyKit/CelestialBody.swift"],
    },
    {
        "id": "supported-dates",
        "migrationIssue": 97,
        "obligation": "Preserve the accepted ephemeris domain, Pluto's narrower domain, all boundary behavior, and failure when an internal search or light-time step leaves the domain.",
        "evidence": ["Tests/AstronomyKitTests/AcceptedTimeRangeTests.swift", "Tests/AstronomyKitTests/PlutoRangeTests.swift", "Tests/AstronomyKitTests/HugeTimeTests.swift"],
    },
    {
        "id": "mutable-state",
        "migrationIssue": 95,
        "obligation": "Preserve captured Delta T behavior, cache keys and reset semantics, fixed-star mutation, gravity simulation ownership, and concurrent access guarantees.",
        "evidence": ["Tests/AstronomyKitTests/DeltaTModelCaptureTests.swift", "Tests/AstronomyKitTests/FixedStarConcurrencyTests.swift", "Tests/AstronomyKitTests/GravitySimulationTests.swift", "Tests/AstronomyKitTests/PlutoThreadSafetyTests.swift"],
    },
]


def run(command, root, **kwargs):
    return subprocess.run(command, cwd=root, check=True, text=True, **kwargs)


def load_symbol_graph(root):
    supplied = os.environ.get("ASTRONOMYKIT_SYMBOL_GRAPH")
    if supplied:
        return json.loads(Path(supplied).read_text())
    run(["swift", "build", "--target", "AstronomyKit"], root, stdout=subprocess.DEVNULL)
    bin_path = subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=root, text=True).strip()
    target_info = json.loads(subprocess.check_output(["swift", "-print-target-info"], cwd=root, text=True))
    target = target_info["target"]
    if platform.system() == "Darwin":
        extractor = subprocess.check_output(["xcrun", "--find", "swift-symbolgraph-extract"], text=True).strip()
        sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
        triple = f'{target["arch"]}-apple-macosx15.0'
    else:
        extractor = "swift-symbolgraph-extract"
        sdk = None
        triple = target["triple"]
    with tempfile.TemporaryDirectory() as directory:
        command = [
            extractor,
            "-module-name",
            "AstronomyKit",
            "-I",
            bin_path,
            "-I",
            str(root / "Sources/CLibAstronomy/include"),
            "-Xcc",
            f"-fmodule-map-file={root / 'Sources/CLibAstronomy/module.modulemap'}",
            "-target",
            triple,
            "-minimum-access-level",
            "public",
            "-output-dir",
            directory,
        ]
        if sdk:
            command.extend(["-sdk", sdk])
        run(command, root, stdout=subprocess.DEVNULL)
        return json.loads((Path(directory) / "AstronomyKit.symbols.json").read_text())


def declaration(symbol):
    return "".join(fragment["spelling"] for fragment in symbol.get("declarationFragments", []))


def source_location(symbol, symbols, parents, root):
    current = symbol
    visited = set()
    while current and current["identifier"]["precise"] not in visited:
        visited.add(current["identifier"]["precise"])
        location = current.get("location")
        if location and location.get("uri"):
            path = Path(unquote(urlparse(location["uri"]).path))
            try:
                relative = path.relative_to(root).as_posix()
            except ValueError:
                relative = path.name
            return relative, location["position"]["line"] + 1
        current = symbols.get(parents.get(current["identifier"]["precise"]))
    return None, None


def public_api(graph, root):
    symbols = {symbol["identifier"]["precise"]: symbol for symbol in graph["symbols"]}
    parents = {
        relationship["source"]: relationship["target"]
        for relationship in graph.get("relationships", [])
        if relationship["kind"] == "memberOf"
    }
    conformances = {}
    for relationship in graph.get("relationships", []):
        if relationship["kind"] == "conformsTo":
            conformances.setdefault(relationship["source"], set()).add(relationship["target"])
    entries = []
    for symbol in graph["symbols"]:
        precise = symbol["identifier"]["precise"]
        path, line = source_location(symbol, symbols, parents, root)
        filename = Path(path).name if path else None
        if filename not in SOURCE_ISSUES:
            raise RuntimeError(f"No migration issue for public symbol {precise} at {path}")
        signature = declaration(symbol)
        top_identifier = precise
        while top_identifier in parents:
            top_identifier = parents[top_identifier]
        top_conformances = conformances.get(top_identifier, set())
        path_components = symbol["pathComponents"]
        mutable_state = "value-or-stateless"
        if path_components[0] == "GravitySimulation":
            mutable_state = "instance-mutable"
        elif path_components[0] == "FixedStar" and any("define" in component.lower() for component in path_components):
            mutable_state = "process-global-mutable"
        contracts = {
            "errors": "throws" if "throws" in signature else "nonthrowing",
            "nil-results": "optional" if "?" in signature or "Optional<" in signature else "nonoptional",
            "serialization": "codable-shape" if {"s:SE", "s:Se"}.issubset(top_conformances) else "not-codable",
            "supported-dates": "accepted-domain-applies" if "AstroTime" in signature or "Date" in signature or path_components[0] in {"AstroTime", "CivilTime"} else "not-time-evaluating",
            "mutable-state": mutable_state,
        }
        entries.append(
            {
                "id": precise,
                "path": ".".join(path_components),
                "kind": symbol["kind"]["identifier"],
                "signature": signature,
                "source": path,
                "line": line,
                "migrationIssue": SOURCE_ISSUES[filename],
                "contracts": contracts,
            }
        )
    return sorted(entries, key=lambda item: item["id"])


def c_dependencies(root):
    header = (root / "Sources/CLibAstronomy/include/astronomy.h").read_text()
    declared = set(re.findall(r"\b(?:Astronomy|_Astronomy|astro|ASTRO|BODY|TIME|DIRECTION|REFRACTION|EQUATOR|ABERRATION)_[A-Za-z0-9_]+\b", header))
    references = {}
    for path in sorted((root / "Sources/AstronomyKit").glob("*.swift")):
        source = path.read_text()
        for identifier in declared.intersection(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", source)):
            references.setdefault(identifier, []).append(path.relative_to(root).as_posix())
    entries = []
    for identifier, paths in references.items():
        issues = sorted({SOURCE_ISSUES[Path(path).name] for path in paths})
        entries.append(
            {
                "id": identifier,
                "migrationIssue": issues[0],
                "additionalMigrationIssues": issues[1:],
                "references": paths,
            }
        )
    return sorted(entries, key=lambda item: item["id"])


def local_patches(root):
    pattern = re.compile(r"^(\d+)\. \*\*(.+?)\.\*\*", re.MULTILINE)
    entries = []
    text = (root / "MAINTAINING.md").read_text()
    for number_text, title in pattern.findall(text):
        number = int(number_text)
        if number in PATCH_ISSUES and number not in {entry["patch"] for entry in entries}:
            entries.append({"id": f"patch-{number:02d}", "patch": number, "title": title, "migrationIssue": PATCH_ISSUES[number]})
        if number == 18:
            break
    if [entry["patch"] for entry in entries] != list(range(1, 19)):
        raise RuntimeError("MAINTAINING.md must contain exactly the 18 mapped local patch groups")
    return entries


def is_generated_source(path):
    with path.open("rb") as stream:
        prefix = stream.read(160).decode("utf-8", errors="ignore")
    return "Generated by " in prefix and "do not edit" in prefix.lower()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def input_hashes(root):
    paths = [
        root / "MAINTAINING.md",
        root / "Sources/CLibAstronomy/include/astronomy.h",
        *sorted((root / "Sources/AstronomyKit").glob("*.swift")),
        *sorted((root / "Tests").rglob("*.swift")),
    ]
    return {path.relative_to(root).as_posix(): sha256(path) for path in paths}


def has_recorded_swift_toolchain(root):
    lock = json.loads((root / "Tools/Migration/Oracle/oracle-lock.json").read_text())
    current = subprocess.check_output(["swift", "--version"], text=True, stderr=subprocess.DEVNULL).splitlines()[0]
    return current == lock["recordedEnvironment"]["swift"]


def generated_artifacts(root):
    paths = sorted(path for path in (root / "Sources").rglob("*") if path.is_file() and is_generated_source(path))
    entries = []
    for path in paths:
        relative = path.relative_to(root).as_posix()
        if relative not in GENERATED_ISSUES:
            raise RuntimeError(f"No migration issue for generated artifact {relative}")
        entries.append({"id": relative, "path": relative, "sha256": sha256(path), "generator": GENERATORS[relative], "migrationIssue": GENERATED_ISSUES[relative]})
    return entries


def test_owners(root):
    entries = []
    for path in sorted((root / "Tests").rglob("*.swift")):
        if path.name not in TEST_ISSUES:
            raise RuntimeError(f"No migration issue for test file {path.name}")
        if path.name in {"JPLValidationTests.swift", "AuditValidationTests.swift"}:
            classification = "independent-reference"
        elif path.name in {"ReproducibilityTests.swift", "PolynomialTests.swift"}:
            classification = "regression-fixture"
        else:
            classification = "invariant"
        source = path.read_text()
        entries.append(
            {
                "id": path.relative_to(root).as_posix(),
                "path": path.relative_to(root).as_posix(),
                "testCount": len(re.findall(r"@Test\b|\bfunc test[A-Za-z0-9_]*\s*\(", source)),
                "classification": classification,
                "migrationIssue": TEST_ISSUES[path.name],
            }
        )
    return entries


def generate_inventory(root, graph, frozen_api=None):
    api = public_api(graph, root) if graph is not None else frozen_api
    if api is None:
        raise RuntimeError("A compiler symbol graph or frozen API inventory is required")
    dependencies = c_dependencies(root)
    patches = local_patches(root)
    artifacts = generated_artifacts(root)
    tests = test_owners(root)
    return {
        "schemaVersion": 1,
        "baselineRevision": BASELINE_REVISION,
        "scope": "AstronomyKit public API and patched C engine migration ownership",
        "inputHashes": input_hashes(root),
        "counts": {
            "publicSwiftAPI": len(api),
            "cDependencies": len(dependencies),
            "localPatches": len(patches),
            "generatedArtifacts": len(artifacts),
            "crossCuttingContracts": len(CROSS_CUTTING_CONTRACTS),
            "testOwners": len(tests),
            "tests": sum(entry["testCount"] for entry in tests),
        },
        "publicSwiftAPI": api,
        "cDependencies": dependencies,
        "localPatches": patches,
        "generatedArtifacts": artifacts,
        "crossCuttingContracts": CROSS_CUTTING_CONTRACTS,
        "testOwners": tests,
    }


def main():
    parser = argparse.ArgumentParser()
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = root / OUTPUT
    existing = json.loads(output.read_text()) if output.exists() else None
    can_extract = bool(os.environ.get("ASTRONOMYKIT_SYMBOL_GRAPH")) or has_recorded_swift_toolchain(root)
    if not can_extract and existing is None:
        raise SystemExit("The recorded Swift toolchain is required for the first inventory generation")
    inventory = generate_inventory(root, load_symbol_graph(root) if can_extract else None, existing["publicSwiftAPI"] if existing else None)
    rendered = json.dumps(inventory, indent=2, sort_keys=True) + "\n"
    if arguments.write:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered)
        print(f"Wrote {OUTPUT} with {inventory['counts']}")
    elif not output.exists() or output.read_text() != rendered:
        raise SystemExit(f"{OUTPUT} is stale; run {Path(__file__).name} --write")
    else:
        mode = "compiler symbol graph" if can_extract else "frozen API plus input hashes"
        print(f"Verified {OUTPUT} with {inventory['counts']} using {mode}")


if __name__ == "__main__":
    main()
