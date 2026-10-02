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
    "IndependentReferenceFixtures.swift": 81,
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

SCRIPT_TEST_ISSUES = {
    "Scripts/migration/test_comparison.py": 80,
    "Scripts/migration/test_foundation.py": 80,
    "Scripts/migration/test_performance.py": 80,
    "Scripts/numerics/solar-altitude/test_bounds.py": 94,
    "Scripts/performance/polynomial/test_polynomial.py": 85,
    "Scripts/performance/test-moon-cache.sh": 95,
    "Scripts/performance/test-nutation-cache.sh": 95,
    "Scripts/performance/test-vsop-cache.sh": 95,
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
    "Scripts/numerics/solar-altitude/bounds.json": 94,
    "Sources/AstronomyKit/SolarAltitudeBounds.swift": 94,
    "Sources/AstronomyKit/UTCOffsetTable.swift": 84,
    "Sources/CLibAstronomy/generated/iau2000b_full.h": 86,
    "Sources/CLibAstronomy/generated/polynomial-data.h": 85,
    "Sources/CLibAstronomy/generated/vsop87b_full.h": 85,
}

GENERATORS = {
    "Scripts/numerics/solar-altitude/bounds.json": "Scripts/numerics/solar-altitude/bounds.py",
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
    swift_version = subprocess.check_output(["swift", "--version"], text=True)
    scratch_path = root / ".build/contract-inventory" / hashlib.sha256(swift_version.encode()).hexdigest()[:16]
    build_options = ["--scratch-path", str(scratch_path)]
    run(["swift", "build", *build_options, "--target", "AstronomyKit"], root, stdout=subprocess.DEVNULL)
    bin_path = subprocess.check_output(["swift", "build", *build_options, "--show-bin-path"], cwd=root, text=True).strip()
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
            str(Path(bin_path) / "Modules"),
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
    signature = "".join(fragment["spelling"] for fragment in symbol.get("declarationFragments", []))
    if "::SYNTHESIZED::" in symbol["identifier"]["precise"]:
        signature = re.sub(r"\b(?:borrowing|consuming)\s+", "", signature)
    return signature


def is_optional_type(type_text):
    normalized = re.sub(r"\s+", "", type_text.split("{", 1)[0])
    return normalized.endswith(("?", "!")) or normalized.startswith(("Optional<", "ImplicitlyUnwrappedOptional<"))


def nil_result_contract(kind, signature):
    if kind == "swift.init":
        return "optional" if re.search(r"\binit[?!]\s*\(", signature) else "nonoptional"
    if "->" in signature:
        return "optional" if is_optional_type(signature.rsplit("->", 1)[1]) else "nonoptional"
    if kind.endswith("property") and ":" in signature:
        return "optional" if is_optional_type(signature.split(":", 1)[1]) else "nonoptional"
    return "nonoptional"


def mutable_state_contract(path_components, kind):
    path = ".".join(path_components)
    if path_components[0] == "GravitySimulation":
        return "instance-mutable"
    if path in {"AstronomyConfig.setDeltaTModel(_:)", "AstronomyConfig.reset()"}:
        return "process-global-mutable"
    if path_components[0] == "FixedStar" and kind == "swift.method":
        return "process-global-mutable"
    return "value-or-stateless"


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
        kind = symbol["kind"]["identifier"]
        contracts = {
            "errors": "throws" if "throws" in signature else "nonthrowing",
            "nil-results": nil_result_contract(kind, signature),
            "serialization": "codable-shape" if {"s:SE", "s:Se"}.issubset(top_conformances) else "not-codable",
            "supported-dates": "accepted-domain-applies" if "AstroTime" in signature or "Date" in signature or path_components[0] in {"AstroTime", "CivilTime"} else "not-time-evaluating",
            "mutable-state": mutable_state_contract(path_components, kind),
        }
        entries.append(
            {
                "id": f"{'.'.join(path_components)}::{kind}::{signature}",
                "path": ".".join(path_components),
                "kind": kind,
                "signature": signature,
                "source": path,
                "line": line,
                "migrationIssue": SOURCE_ISSUES[filename],
                "contracts": contracts,
            }
        )
    return sorted(entries, key=lambda item: item["id"])


def c_typedefs(header):
    without_comments = re.sub(r"/\*.*?\*/", "", header, flags=re.DOTALL)
    names = set(re.findall(r"\btypedef\b[^;{}]*?\(\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\([^;{}]*\)\s*;", without_comments))
    names.update(re.findall(r"}\s*([A-Za-z_][A-Za-z0-9_]*)\s*;", without_comments))
    for match in re.finditer(r"\btypedef\b(?P<body>[^;{}]+);", without_comments):
        body = match.group("body").strip()
        if "(*" in body:
            continue
        name = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*$", body)
        if name:
            names.add(name.group(1))
    return names


def c_structs(header, typedefs):
    without_comments = re.sub(r"/\*.*?\*/", "", header, flags=re.DOTALL)
    structs = {}
    for match in re.finditer(r"typedef\s+struct(?:\s+[A-Za-z_][A-Za-z0-9_]*)?\s*\{(?P<body>.*?)\}\s*(?P<name>astro_[A-Za-z0-9_]+_t)\s*;", without_comments, re.DOTALL):
        fields = {}
        for declaration_text in match.group("body").split(";"):
            field = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^]]*\]\s*)*$", declaration_text.strip())
            if field:
                fields[field.group(1)] = typedefs.intersection(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", declaration_text))
        structs[match.group("name")] = fields
    return structs


def c_dependencies(root):
    header = (root / "Sources/CLibAstronomy/include/astronomy.h").read_text()
    types = c_typedefs(header)
    structs = c_structs(header, types)
    functions = set(re.findall(r"\b(Astronomy_[A-Za-z0-9_]+)\s*\(", header))
    constants = set(re.findall(r"^\s*([A-Z][A-Z0-9_]+)\s*(?:=|,|$)", re.sub(r"/\*.*?\*/", "", header, flags=re.DOTALL), re.MULTILINE))
    declared = functions | types | constants
    return_types = {
        function: return_type
        for return_type, function in re.findall(r"\b(astro_[A-Za-z0-9_]+_t)\s+(Astronomy_[A-Za-z0-9_]+)\s*\(", header)
    }
    references = {}
    referenced_types = set()
    for path in sorted((root / "Sources/AstronomyKit").glob("*.swift")):
        source = path.read_text()
        relative = path.relative_to(root).as_posix()
        identifiers = set(re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", source))
        for identifier in declared.intersection(identifiers):
            references.setdefault(identifier, set()).add(relative)
            if identifier in types:
                referenced_types.add(identifier)
            if identifier in return_types:
                referenced_types.add(return_types[identifier])
    pending = list(referenced_types)
    while pending:
        struct = pending.pop()
        for nested_types in structs.get(struct, {}).values():
            for nested in nested_types:
                if nested not in referenced_types:
                    referenced_types.add(nested)
                    pending.append(nested)
    for struct in referenced_types:
        struct_references = references.get(struct, set())
        if not struct_references:
            struct_references = {
                reference
                for function, return_type in return_types.items()
                if return_type == struct
                for reference in references.get(function, set())
            }
        references.setdefault(struct, set()).update(struct_references)
        for field in structs.get(struct, {}):
            references.setdefault(f"{struct}.{field}", set()).update(struct_references)
    entries = []
    for identifier, paths in references.items():
        issues = sorted({SOURCE_ISSUES[Path(path).name] for path in paths})
        entries.append(
            {
                "id": identifier,
                "migrationIssue": issues[0],
                "additionalMigrationIssues": issues[1:],
                "references": sorted(paths),
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
    tests = [root / path for path in test_paths(root)]
    paths = [
        root / "MAINTAINING.md",
        root / "Sources/CLibAstronomy/include/astronomy.h",
        *sorted((root / "Sources/AstronomyKit").glob("*.swift")),
        *tests,
    ]
    return {path.relative_to(root).as_posix(): sha256(path) for path in paths}


def load_inventory_symbol_graph(root):
    return load_symbol_graph(root)


def generated_artifacts(root):
    marked = {path.relative_to(root).as_posix() for search_root in (root / "Sources", root / "Scripts") for path in search_root.rglob("*") if path.is_file() and is_generated_source(path)}
    discovered = marked | set(GENERATED_ISSUES)
    entries = []
    for relative in sorted(discovered):
        path = root / relative
        if not path.is_file():
            raise RuntimeError(f"Generated artifact is missing: {relative}")
        if relative not in GENERATED_ISSUES:
            raise RuntimeError(f"No migration issue for generated artifact {relative}")
        entries.append({"id": relative, "path": relative, "sha256": sha256(path), "generator": GENERATORS[relative], "migrationIssue": GENERATED_ISSUES[relative]})
    return entries


def test_paths(root):
    paths = {path.relative_to(root).as_posix() for path in (root / "Tests").rglob("*.swift")}
    paths.update(path.relative_to(root).as_posix() for path in (root / "Scripts").rglob("test_*.py"))
    paths.update(path.relative_to(root).as_posix() for path in (root / "Scripts").rglob("test-*.sh"))
    return paths


def test_owners(root):
    entries = []
    for relative in sorted(test_paths(root)):
        path = root / relative
        issue = TEST_ISSUES.get(path.name, SCRIPT_TEST_ISSUES.get(relative))
        if issue is None:
            raise RuntimeError(f"No migration issue for test file {relative}")
        if path.name in {"JPLValidationTests.swift", "AuditValidationTests.swift", "IndependentReferenceFixtures.swift"}:
            classification = "independent-reference"
        elif path.name in {"ReproducibilityTests.swift", "PolynomialTests.swift"}:
            classification = "regression-fixture"
        elif relative == "Scripts/migration/test_comparison.py":
            classification = "independent-reference"
        elif relative == "Scripts/migration/test_foundation.py" or path.suffix == ".sh":
            classification = "smoke"
        else:
            classification = "invariant"
        source = path.read_text()
        if path.suffix == ".swift":
            test_count = len(re.findall(r"@Test\b|\bfunc test[A-Za-z0-9_]*\s*\(", source))
        elif path.suffix == ".py":
            test_count = len(re.findall(r"^\s*def test_[A-Za-z0-9_]*\s*\(", source, re.MULTILINE))
        else:
            test_count = 1
        entries.append(
            {
                "id": relative,
                "path": relative,
                "testCount": test_count,
                "classification": classification,
                "migrationIssue": issue,
            }
        )
    return entries


def generate_inventory(root, graph):
    api = public_api(graph, root)
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
    inventory = generate_inventory(root, load_inventory_symbol_graph(root))
    rendered = json.dumps(inventory, indent=2, sort_keys=True) + "\n"
    if arguments.write:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered)
        print(f"Wrote {OUTPUT} with {inventory['counts']}")
    elif not output.exists() or output.read_text() != rendered:
        raise SystemExit(f"{OUTPUT} is stale; run {Path(__file__).name} --write")
    else:
        print(f"Verified {OUTPUT} with {inventory['counts']} using the current compiler symbol graph")


if __name__ == "__main__":
    main()
