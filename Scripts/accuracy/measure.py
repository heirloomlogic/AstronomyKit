#!/usr/bin/env python3
"""Measure local roots without claiming search completeness or absolute precision."""
import argparse
import ctypes
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import subprocess

from models import ROOT, build

FIXTURES = Path(__file__).parent / "fixtures"
EPOCH = dt.datetime(2000, 1, 1, 12, tzinfo=dt.timezone.utc)
BODIES = ["mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune", "pluto", "sun", "moon"]


def signed(x):
    return (x + 180) % 360 - 180


class Model:
    def __init__(self, path):
        self.library = ctypes.CDLL(str(path))
        self.sample = self.library.ak_sample
        self.sample.argtypes = [ctypes.c_int, ctypes.c_double, ctypes.c_int,
                                ctypes.POINTER(ctypes.c_double)]
        self.sample.restype = ctypes.c_int

    def position(self, body, ut, mode=0):
        output = (ctypes.c_double * 3)()
        status = self.sample(BODIES.index(body), ut, mode, output)
        if status or not all(math.isfinite(x) for x in output):
            raise ValueError(f"Ephemeris sample unavailable: {body} {ut}, status={status}")
        return list(output)

    def speed(self, body, ut, width=0.0007):
        return signed(self.position(body, ut + width/2)[0]
                      - self.position(body, ut - width/2)[0]) / width


def fixtures():
    provenance = json.loads((FIXTURES / "provenance.json").read_text())
    for name, checksum in provenance["files"].items():
        data = (FIXTURES / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != checksum:
            raise ValueError(f"Frozen reference changed: {name}")
        yield name[:3], json.loads(data)["oracleOutput"]


def refine(residual):
    def checked(seconds):
        value = residual(seconds)
        if not math.isfinite(value):
            raise ValueError("Non-finite residual cannot certify a root")
        return value

    width = 10.0
    while checked(-width) * checked(width) > 0 and width < 86400:
        width = min(86400, width * 2)
    lower, upper = -width, width
    low, high = checked(lower), checked(upper)
    if low * high > 0:
        raise ValueError("No local sign bracket within one day")
    while upper - lower > 0.001:
        middle = (lower + upper) / 2
        value = checked(middle)
        if low * value <= 0:
            upper = middle
        else:
            lower, low = middle, value
    offset = (lower + upper) / 2
    return offset, upper-lower, checked(offset)


def measure(model):
    rows = []
    for case, oracle in fixtures():
        for index, event in enumerate(oracle["events"]):
            kind = event["kind"]
            if kind not in {"station", "aspect", "phaseBoundary", "solarBandCrossing", "signIngress"}:
                continue  # Six house/angle cases require the production Swift probe.
            time = (dt.datetime.fromisoformat(event["instant"]) - EPOCH).total_seconds() / 86400
            bodies = event["bodies"]

            def residual(seconds):
                at = time + seconds / 86400
                if kind == "station":
                    return model.speed(bodies[0], at)
                longitude = model.position(bodies[0], at)[0]
                if kind == "signIngress":
                    return signed(longitude - event["targetDegrees"])
                return signed(longitude - model.position(bodies[1], at)[0] - event["signedBranchDegrees"])

            offset, width, remaining = refine(residual)
            limit = 1e-6 if kind == "station" else 1e-4
            row = dict(caseID=case, eventIndex=index, identity=event, signedTimeErrorSeconds=offset,
                       bracketWidthSeconds=width, localResidual=remaining,
                       residualUnit="degrees/day" if kind == "station" else "degrees",
                       referenceInstantResidual=residual(0), passesTimeGate=abs(offset) <= 60,
                       passesConvergence=width <= 1 and abs(remaining) <= limit)
            row["referenceEpochSamples"] = {
                b: {"longitudeDegrees": model.position(b, time)[0], "speedDegreesPerDay": model.speed(b, time)}
                for b in bodies}
            if kind == "station":
                row["accelerationDegreesPerDaySquared"] = (
                    model.speed(bodies[0], time + .01) - model.speed(bodies[0], time - .01)) / .02
                row["differenceWidthRootsSeconds"] = {
                    str(h): refine(lambda s: model.speed(bodies[0], time+s/86400, h))[0]
                    for h in (.00035, .0007, .0014, .007)}
            rows.append(row)
    if len(rows) != 30:
        raise ValueError(f"Expected 30 native events, found {len(rows)}")
    return rows


def production(libraries, products, module_map, output):
    """Relink compiled, unchanged Swift production observations to each isolated C model."""
    records = {}
    for name, library in libraries.items():
        print(f"Measuring relinked Swift observations: {name}", flush=True)
        executable = output / f"production-{name}"
        subprocess.run(["swiftc", "-I", str(products), "-Xcc", f"-fmodule-map-file={module_map}",
                        str(ROOT / "Scripts/accuracy/production-probe.swift"),
                        str(products / "AstrologyKit.o"), str(products / "AstronomyKit.o"),
                        library["path"], "-o", str(executable)], check=True)
        for frame in (["legacy", "date"] if name == "baseline" else ["date"]):
            import os
            report = output / f"production-{name}-{frame}.json"
            subprocess.run([str(executable), str(FIXTURES.resolve()), str(report)], check=True,
                           env={**os.environ, "ASTROLOGY_PROBE_DATE_ROTATION": str(int(frame == "date")),
                                "ASTROLOGY_PROBE_MODEL": name}, stdout=subprocess.DEVNULL)
            data = json.loads(report.read_text())
            if len(data["results"]) != 36 or any("error" in r for r in data["results"]):
                raise ValueError("Production probe did not refine all 36 events")
            records[f"{name}-{frame}"] = data
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/accuracy")
    parser.add_argument("--products", type=Path, help="Built AstrologyKit Debug products directory")
    parser.add_argument("--module-map", type=Path, help="CLibAstronomy module.modulemap matching the Swift objects")
    parser.add_argument("--require-pass", action="store_true")
    args = parser.parse_args()
    if bool(args.products) != bool(args.module_map):
        parser.error("--products and --module-map must be supplied together")
    output = args.output.resolve()
    libraries = build(output)
    report = {"purpose": "Local root accuracy diagnostics; not certified search coverage",
              "libraries": libraries, "native": {name: measure(Model(record["path"])) for name, record in libraries.items()}}
    if args.products:
        report["production"] = production(libraries, args.products.resolve(), args.module_map.resolve(), output)
        report["swiftInputSHA256"] = {
            name: hashlib.sha256((args.products / name).read_bytes()).hexdigest()
            for name in ("AstrologyKit.o", "AstronomyKit.o")}
        report["moduleMapSHA256"] = hashlib.sha256(args.module_map.read_bytes()).hexdigest()
    report["compiler"] = subprocess.check_output(["clang", "--version"], text=True).strip()
    report["sourceFilesSHA256"] = {
        str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted((ROOT / "Scripts/accuracy").glob("*.py"))
        + sorted((ROOT / "Scripts/accuracy").glob("*.c"))
        + sorted((ROOT / "Scripts/accuracy").glob("*.inc"))
        + sorted((ROOT / "Scripts/accuracy").glob("*.swift"))
        + sorted((ROOT / "Sources/CLibAstronomy/generated").glob("*.h"))
        + sorted((ROOT / "Sources/CLibAstronomy/detmath").glob("*")) if path.is_file()}
    (output / "matrix.json").write_text(json.dumps(report, indent=2) + "\n")
    for name, rows in report["native"].items():
        print(name, "native failures:", sum(not r["passesTimeGate"] for r in rows),
              "max seconds:", max(abs(r["signedTimeErrorSeconds"]) for r in rows))
    passed = all(r["passesTimeGate"] and r["passesConvergence"] for r in report["native"]["full"])
    if args.products:
        for name, data in report["production"].items():
            rows = data["results"]
            print(name, "production failures:", sum(not r["passes60SecondReferenceGate"] for r in rows),
                  "max seconds:", max(r["absoluteTimeErrorSeconds"] for r in rows))
        for row in report["production"]["full-date"]["results"]:
            limit = 1e-6 if row["kind"] == "station" else 1e-4
            passed &= row["passes60SecondReferenceGate"] and row["bracketWidthSeconds"] <= 1 and abs(row["localResidual"]) <= limit
    if args.require_pass and (not passed or not args.products):
        raise SystemExit("B369-ASTRONOMY-60S remains blocked; full production acceptance is required")


if __name__ == "__main__":
    main()
