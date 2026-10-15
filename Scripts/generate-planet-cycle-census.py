#!/usr/bin/env python3
"""Capture dense direct-SPK planetary crossing censuses for issue 248."""
import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import tempfile


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Scripts/planet-data/de441-cycle-census.json"
FOUNDATION = ROOT / "Scripts/planet-data/de441-foundation.json"
CLOCK = ROOT / "Scripts/apparent-place-data/dtdb.c"
J2000 = 2_451_545.0
AU_KM = 149_597_870.7
STEP_DAYS = 0.125
ROOT_TOLERANCE_SECONDS = 0.01
BODIES = {
    "jupiter": {"periodDays": 4_332.589, "preferredStartTT": 0.0, "barycenter": "jupiterBarycenter", "offset": "jupiterOffset"},
    "uranus": {"periodDays": 30_685.4, "preferredStartTT": 0.0, "barycenter": "uranusBarycenter", "offset": "uranusOffset"},
    "neptune": {"periodDays": 60_189.0, "preferredStartTT": -35_000.0, "barycenter": "neptuneBarycenter", "offset": "neptuneOffset"},
}


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


foundation = load_module("planet_de441_generator", ROOT / "Scripts/generate-planet-de441.py")
clock = load_module("planet_source_clock", ROOT / "Scripts/qualify-planet-source-model.py")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def source_hashes():
    paths = [
        Path(__file__),
        FOUNDATION,
        CLOCK,
        ROOT / "Scripts/generate-planet-de441.py",
        ROOT / "Scripts/assess-moon-de441.py",
        ROOT / "Scripts/qualify-planet-source-model.py",
    ]
    return {str(path.relative_to(ROOT)): digest(path.read_bytes()) for path in paths}


def tt_to_tdb(tt):
    return tt + float(clock.offset_seconds(clock.mp.mpf(tt))) / 86_400


def tdb_to_tt(tdb):
    tt = tdb
    for _ in range(4):
        tt = tdb - float(clock.offset_seconds(clock.mp.mpf(tt))) / 86_400
    return tt


class Table:
    def __init__(self, records):
        self.records = records
        self.start = records[0][0]
        self.days = records[0][1]
        self.end = records[-1][0] + records[-1][1]

    def state(self, jd_tdb):
        index = min(math.floor((jd_tdb - self.start) / self.days), len(self.records) - 1)
        if index < 0 or not self.start <= jd_tdb < self.end:
            raise ValueError("source census epoch is outside its component")
        start, days, axes = self.records[index]
        x = 2 * (jd_tdb - start) / days - 1
        if not -1 <= x <= 1:
            raise ValueError("source census selected the wrong record")
        return foundation.evaluate(axes, x, days)


class DirectSource:
    def __init__(self, barycenter, sun, offset):
        self.barycenter = barycenter
        self.sun = sun
        self.offset = offset

    def state(self, tdb, physical_center=True):
        barycenter = self.barycenter.state(J2000 + tdb)
        sun = self.sun.state(J2000 + tdb)
        offset = self.offset.state(J2000 + tdb) if physical_center else ((0.0,) * 3,) * 2
        return tuple(tuple(barycenter[k][axis] - sun[k][axis] + offset[k][axis] for axis in range(3)) for k in range(2))

    def rate(self, tdb, physical_center=True):
        position, velocity = self.state(tdb, physical_center)
        return sum(a * b for a, b in zip(position, velocity)) / math.hypot(*position)

    def distance(self, tdb, physical_center=True):
        return math.hypot(*self.state(tdb, physical_center)[0]) / AU_KM


def refine(function, lower, upper):
    left = function(lower)
    right = function(upper)
    if not all(map(math.isfinite, [left, right])) or left == 0 or right == 0 or left * right > 0:
        raise ValueError("crossing bracket is invalid")
    while (upper - lower) * 86_400 > ROOT_TOLERANCE_SECONDS:
        middle = (lower + upper) / 2
        value = function(middle)
        if not math.isfinite(value) or middle in (lower, upper):
            raise ValueError("crossing refinement did not progress")
        if left * value <= 0:
            upper = middle
            right = value
        else:
            lower = middle
            left = value
    return lower, upper, left, right


def crossing_digest(crossings):
    return digest((json.dumps(crossings, sort_keys=True, separators=(",", ":")) + "\n").encode())


def scan_cycle(rate, start, end, step, distance=None):
    if not all(map(math.isfinite, [start, end, step])) or not start < end or step <= 0:
        raise ValueError("invalid census span")
    count = math.ceil((end - start) / step) + 1
    epochs = [min(start + index * step, end) for index in range(count)]
    if epochs[-1] != end:
        epochs.append(end)
    values = [rate(epoch) for epoch in epochs]
    if not all(map(math.isfinite, values)):
        raise ValueError("dense census encountered a nonfinite sample")
    crossings = []
    index = 0
    while index < len(epochs) - 1:
        if values[index] == 0:
            first = index
            while index + 1 < len(values) and values[index + 1] == 0:
                index += 1
            if first == 0 or index + 1 == len(values) or values[first - 1] * values[index + 1] >= 0:
                raise ValueError("exact-zero sample does not identify one interior crossing")
            left, right = values[first - 1], values[index + 1]
            lower, upper = epochs[first], epochs[index]
            root = (lower + upper) / 2
            kind = "pericenter" if left < 0 < right else "apocenter"
            crossings.append({"kind": kind, "lower": lower, "upper": upper, "root": root, "distance": distance(root) if distance else (-math.cos(root))})
            index += 1
            continue
        lower, upper, left, right = epochs[index], epochs[index + 1], values[index], values[index + 1]
        index += 1
        if right == 0:
            continue
        if left * right >= 0:
            continue
        lo, hi, first, second = refine(rate, lower, upper)
        root = (lo + hi) / 2
        kind = "pericenter" if first < 0 < second else "apocenter"
        crossings.append(
            {
                "kind": kind,
                "lower": lo,
                "upper": hi,
                "root": root,
                "distance": distance(root) if distance else (-math.cos(root)),
            }
        )
    if not crossings or any(a["kind"] == b["kind"] for a, b in zip(crossings, crossings[1:])):
        raise ValueError("dense census crossing sequence is incomplete")
    principal = []
    if any(row["kind"] == "pericenter" for row in crossings):
        principal.append(min((row for row in crossings if row["kind"] == "pericenter"), key=lambda row: row["distance"]))
    if any(row["kind"] == "apocenter" for row in crossings):
        principal.append(max((row for row in crossings if row["kind"] == "apocenter"), key=lambda row: row["distance"]))
    principal.sort(key=lambda row: row["root"])
    return {
        "sampleCount": len(epochs),
        "endpointRates": [values[0], values[-1]],
        "crossings": crossings,
        "principal": principal,
    }


def load_sources(cache):
    manifest = json.loads(FOUNDATION.read_bytes())
    readers = {
        name: foundation.CachedReader(name, cache, row["retrievedByteRangesSHA256"])
        for name, row in manifest["sources"].items()
    }
    required = {"sun"} | {config[key] for config in BODIES.values() for key in ("barycenter", "offset")}
    tables = {name: Table(foundation.load_component(readers[component.source], component)) for name, component in foundation.COMPONENTS.items() if name in required}
    return {body: DirectSource(tables[config["barycenter"]], tables["sun"], tables[config["offset"]]) for body, config in BODIES.items()}


def select_span(source, config):
    period = config["periodDays"]
    candidates = []
    for offset in range(-128, 129):
        start = config["preferredStartTT"] + offset
        end = start + period
        rates = [source.rate(tt_to_tdb(epoch), False) for epoch in (start, end)]
        candidates.append((min(map(abs, rates)), start, rates))
    _, start, rates = max(candidates)
    if rates[0] * rates[1] <= 0:
        raise ValueError("source-selected cycle endpoints do not share a stable radial direction")
    return start, start + period


def capture(cache):
    cases = {}
    for body, source in load_sources(cache).items():
        config = BODIES[body]
        start_tt, end_tt = select_span(source, config)
        start_tdb, end_tdb = tt_to_tdb(start_tt), tt_to_tdb(end_tt)
        physical = scan_cycle(source.rate, start_tdb, end_tdb, STEP_DAYS, source.distance)
        converged = scan_cycle(source.rate, start_tdb, end_tdb, STEP_DAYS / 2, source.distance)
        system = scan_cycle(lambda epoch: source.rate(epoch, False), start_tdb, end_tdb, STEP_DAYS, lambda epoch: source.distance(epoch, False))
        system_converged = scan_cycle(lambda epoch: source.rate(epoch, False), start_tdb, end_tdb, STEP_DAYS / 2, lambda epoch: source.distance(epoch, False))
        if [row["kind"] for row in physical["crossings"]] != [row["kind"] for row in converged["crossings"]]:
            raise ValueError("half-step physical-center census found a different crossing inventory")
        if [row["kind"] for row in system["crossings"]] != [row["kind"] for row in system_converged["crossings"]]:
            raise ValueError("half-step system-center census found a different crossing inventory")
        physical_maximum_delta = max(abs(a["root"] - b["root"]) * 86_400 for a, b in zip(physical["crossings"], converged["crossings"]))
        system_maximum_delta = max(abs(a["root"] - b["root"]) * 86_400 for a, b in zip(system["crossings"], system_converged["crossings"]))

        def rows(measured):
            result = []
            for index, row in enumerate(measured["crossings"]):
                result.append(
                {
                    "index": index,
                    "kind": row["kind"],
                    "lowerTT": tdb_to_tt(row["lower"]),
                    "upperTT": tdb_to_tt(row["upper"]),
                    "tt": tdb_to_tt(row["root"]),
                    "distanceAU": row["distance"],
                }
            )
            return result

        physical_crossings = rows(physical)
        system_crossings = rows(system)
        system_principal_indices = [min(range(len(system_crossings)), key=lambda index: abs(system_crossings[index]["tt"] - tdb_to_tt(row["root"]))) for row in system["principal"]]
        principal_indices = [min((row["index"] for row in physical_crossings if row["kind"] == system_crossings[system_index]["kind"]), key=lambda index: abs(physical_crossings[index]["tt"] - system_crossings[system_index]["tt"])) for system_index in system_principal_indices]
        cases[body] = {
            "periodDays": config["periodDays"],
            "spanTT": [start_tt, end_tt],
            "sampleStepDays": STEP_DAYS,
            "physicalSampleCount": physical["sampleCount"],
            "physicalEndpointRangeRatesKmPerDay": physical["endpointRates"],
            "systemEndpointRangeRatesKmPerDay": system["endpointRates"],
            "physicalCrossingCount": len(physical_crossings),
            "physicalCrossingSHA256": crossing_digest(physical_crossings),
            "physicalCrossings": physical_crossings,
            "systemCrossingCount": len(system_crossings),
            "systemCrossingSHA256": crossing_digest(system_crossings),
            "systemCrossings": system_crossings,
            "systemPrincipalCrossingIndices": system_principal_indices,
            "principalPhysicalCrossingIndices": principal_indices,
            "halfStepConvergence": {
                "sampleStepDays": STEP_DAYS / 2,
                "physicalCrossingCount": len(converged["crossings"]),
                "physicalMaximumRootDeltaSeconds": physical_maximum_delta,
                "systemCrossingCount": len(system_converged["crossings"]),
                "systemMaximumRootDeltaSeconds": system_maximum_delta,
            },
        }
        print(f"{body}: {len(physical_crossings)} physical and {len(system_crossings)} system crossings; system principal {system_principal_indices}; physical principal {principal_indices}; half-step deltas {physical_maximum_delta:.6g}/{system_maximum_delta:.6g} s", flush=True)
    result = {
        "schemaVersion": 1,
        "foundationSHA256": digest(FOUNDATION.read_bytes()),
        "sourceSHA256": source_hashes(),
        "method": {
            "selection": "For each nominal complete orbital period, choose the daily start within 128 days of the stated preferred epoch that maximizes the smaller absolute direct-source endpoint range rate.",
            "sampling": "Evaluate the direct physical-center SPK composition every three hours, retain sign changes and exact-zero samples, bisect each bracket, and repeat at half the step to require the same crossing inventory.",
            "rootToleranceSeconds": ROOT_TOLERANCE_SECONDS,
            "clock": "Source records and scanning use TDB; recorded roots and spans use TT through the pinned ERFA geocentric TDB-minus-TT series.",
            "frameCenter": "ICRF physical planet center minus DE441 Sun center. The system-center trajectory selects one principal pericenter and apocenter, each matched to the nearest same-kind physical-center crossing. Uranus uses the issue-authorized DE442 barycenter embedded in URA184.",
        },
        "cases": cases,
    }
    return validate(result)


def validate(result):
    if set(result) != {"schemaVersion", "foundationSHA256", "sourceSHA256", "method", "cases"} or result["schemaVersion"] != 1:
        raise ValueError("census schema differs")
    if result["foundationSHA256"] != digest(FOUNDATION.read_bytes()) or result["sourceSHA256"] != source_hashes():
        raise ValueError("census source binding differs")
    if set(result["cases"]) != set(BODIES) or result["method"].get("rootToleranceSeconds") != ROOT_TOLERANCE_SECONDS:
        raise ValueError("census body or method inventory differs")
    for body, config in BODIES.items():
        case = result["cases"][body]
        expected_keys = {"periodDays", "spanTT", "sampleStepDays", "physicalSampleCount", "physicalEndpointRangeRatesKmPerDay", "systemEndpointRangeRatesKmPerDay", "physicalCrossingCount", "physicalCrossingSHA256", "physicalCrossings", "systemCrossingCount", "systemCrossingSHA256", "systemCrossings", "systemPrincipalCrossingIndices", "principalPhysicalCrossingIndices", "halfStepConvergence"}
        if set(case) != expected_keys or case["periodDays"] != config["periodDays"] or case["sampleStepDays"] != STEP_DAYS:
            raise ValueError("census case contract differs")
        start, end = case["spanTT"]
        if not all(map(math.isfinite, [start, end])) or abs((end - start) - config["periodDays"]) > 1e-9:
            raise ValueError("census does not cover one complete nominal cycle")
        crossings = case["physicalCrossings"]
        if case["physicalCrossingCount"] != len(crossings) or case["physicalCrossingSHA256"] != crossing_digest(crossings):
            raise ValueError("census crossing inventory differs")
        if len(crossings) < 2 or any(set(row) != {"index", "kind", "lowerTT", "upperTT", "tt", "distanceAU"} for row in crossings):
            raise ValueError("census crossing rows differ")
        if [row["index"] for row in crossings] != list(range(len(crossings))) or any(a["tt"] >= b["tt"] or a["kind"] == b["kind"] for a, b in zip(crossings, crossings[1:])):
            raise ValueError("census crossing order differs")
        if any(row["kind"] not in ("pericenter", "apocenter") or not row["lowerTT"] <= row["tt"] <= row["upperTT"] or (row["upperTT"] - row["lowerTT"]) * 86_400 > 1.01 * ROOT_TOLERANCE_SECONDS or not math.isfinite(row["distanceAU"]) for row in crossings):
            raise ValueError("census crossing value differs")
        system = case["systemCrossings"]
        if case["systemCrossingCount"] != len(system) or len(system) < 2 or case["systemCrossingSHA256"] != crossing_digest(system) or {row["kind"] for row in system} != {"pericenter", "apocenter"} or any(a["tt"] >= b["tt"] or a["kind"] == b["kind"] for a, b in zip(system, system[1:])):
            raise ValueError("census system crossing inventory differs")
        system_principal = case["systemPrincipalCrossingIndices"]
        if len(system_principal) != 2 or len(set(system_principal)) != 2 or any(not 0 <= index < len(system) for index in system_principal):
            raise ValueError("census system principal inventory differs")
        selected_system = [system[index] for index in system_principal]
        if {row["kind"] for row in selected_system} != {"pericenter", "apocenter"} or min((row for row in system if row["kind"] == "pericenter"), key=lambda row: row["distanceAU"])["index"] not in system_principal or max((row for row in system if row["kind"] == "apocenter"), key=lambda row: row["distanceAU"])["index"] not in system_principal:
            raise ValueError("census system principal selection differs")
        principal = case["principalPhysicalCrossingIndices"]
        if len(principal) != 2 or len(set(principal)) != 2 or any(not 0 <= index < len(crossings) for index in principal):
            raise ValueError("census principal inventory differs")
        selected = [crossings[index] for index in principal]
        if {row["kind"] for row in selected} != {"pericenter", "apocenter"}:
            raise ValueError("census principal kinds differ")
        nearest = {min((row for row in crossings if row["kind"] == source["kind"]), key=lambda row: abs(row["tt"] - source["tt"]))["index"] for source in selected_system}
        if {row["index"] for row in selected} != nearest:
            raise ValueError("census principal selection differs")
        convergence = case["halfStepConvergence"]
        if convergence.get("sampleStepDays") != STEP_DAYS / 2 or convergence.get("physicalCrossingCount") != len(crossings) or convergence.get("systemCrossingCount") != len(system) or not 0 <= convergence.get("physicalMaximumRootDeltaSeconds", math.inf) <= ROOT_TOLERANCE_SECONDS or not 0 <= convergence.get("systemMaximumRootDeltaSeconds", math.inf) <= ROOT_TOLERANCE_SECONDS:
            raise ValueError("census half-step convergence differs")
        if case["physicalEndpointRangeRatesKmPerDay"][0] * case["physicalEndpointRangeRatesKmPerDay"][1] <= 0 or case["systemEndpointRangeRatesKmPerDay"][0] * case["systemEndpointRangeRatesKmPerDay"][1] <= 0:
            raise ValueError("census endpoint direction differs")
    return result


def atomic_write(path, data):
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--capture", action="store_true")
    group.add_argument("--check", action="store_true")
    parser.add_argument("--cache", type=Path, default=ROOT / ".context/issue-248/ranges")
    args = parser.parse_args()
    if args.capture:
        result = capture(args.cache)
        atomic_write(OUTPUT, (json.dumps(result, indent=2, sort_keys=True) + "\n").encode())
        print(f"Recorded direct-source complete-cycle census: {OUTPUT.relative_to(ROOT)}")
    else:
        validate(json.loads(OUTPUT.read_bytes()))
        print("Verified direct-source complete-cycle census")


if __name__ == "__main__":
    main()
