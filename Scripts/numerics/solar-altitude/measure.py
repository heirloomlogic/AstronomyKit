#!/usr/bin/env python3
"""Measure the floating-point error of the geometric solar altitude path.

Builds the vendored engine as shipped (binary64) and rewritten to __float128
with every literal taken exactly (quad_transform.py), runs both over the
same grid through probe.c, and compares the results exactly. The reference
carries about 113 bits, so the difference is the binary64 path's rounding
and libm error. See <doc:SolarAltitudeNumerics>.

Needs a C compiler with libquadmath (GCC; QUAD_CC selects it). `--check`
runs the reduced grid and fails when a column exceeds its ceiling in
bounds.json.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from decimal import Decimal, getcontext
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "Scripts/performance/polynomial"))
import embed  # noqa: E402

ENGINE = ROOT / "Sources/CLibAstronomy"
SOURCES = ["astronomy.c", "polynomial.h", "include/astronomy.h", "generated/polynomial-data.h", "generated/vsop87b_full.h", "generated/iau2000b_full.h"]
START, STOP = embed.START, embed.STOP
OBSERVERS = [(40.0, 0.0, 0.0), (0.0, 0.0, 0.0), (66.5, 120.0, 0.0), (-35.0, -70.0, 1000.0), (89.9, 0.0, 0.0), (-89.9, 180.0, 0.0)]
COLUMNS = ["altitude_deg", "azimuth_deg", "ra_hours", "dec_deg", "dist_au", "ra_j2000_hours", "dec_j2000_deg", "geo_x_au", "geo_y_au", "geo_z_au", "earth_x_au", "earth_y_au", "earth_z_au", "sidereal_hours", "deltat_s"]
PERIOD = {"azimuth_deg": Decimal(360), "ra_hours": Decimal(24), "ra_j2000_hours": Decimal(24), "sidereal_hours": Decimal(24)}
getcontext().prec = 60


def find_quad_compiler():
    probe = "#include <quadmath.h>\nint main(void){__float128 x=1; return (int)sinq(x);}\n"
    with tempfile.TemporaryDirectory() as directory:
        source = Path(directory) / "q.c"
        source.write_text(probe)
        for cc in [os.environ.get("QUAD_CC"), "gcc", "gcc-15", "gcc-14", "gcc-13"]:
            if cc and shutil.which(cc):
                run = subprocess.run([cc, "-std=gnu11", str(source), "-o", str(Path(directory) / "q"), "-lquadmath"], capture_output=True)
                if run.returncode == 0:
                    return cc
    return None


def compile_probe(cc, tree, binary, flags):
    command = [cc, *flags, "-pthread", "-I", str(tree / "include"), "-I", str(tree), str(tree / "astronomy.c"), str(HERE / "probe.c"), "-o", str(binary), "-lm"]
    if "-DQUAD" in flags:
        command.append("-lquadmath")
    subprocess.run(command, check=True)
    return binary


def build_quad(directory, cc):
    tree = directory / "quad"
    for name in SOURCES:
        (tree / name).parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([sys.executable, str(HERE / "quad_transform.py"), str(ENGINE / name), str(tree / name)], check=True)
    return compile_probe(cc, tree, tree / "probe", ["-std=gnu11", "-O2", "-DQUAD"])


def grid(step, outside):
    spans = [(START - 36525.0, START), (STOP, STOP + 36525.0)] if outside else [(START, STOP)]
    lines = []
    for low, high in spans:
        i = 0
        while low + i * step < high:
            tt = low + i * step
            ut = tt - 0.00075  # about 65 s; any pair is a valid input
            for lat, lon, height in OBSERVERS:
                lines.append(f"{tt.hex()} {ut.hex()} {float(lat).hex()} {float(lon).hex()} {float(height).hex()}\n")
            i += 1
    return "".join(lines)


def run(binary, inputs):
    return subprocess.run([str(binary)], input=inputs, capture_output=True, text=True, check=True).stdout.splitlines()


def compare(double_lines, quad_lines, input_lines):
    worst = {name: (Decimal(0), "") for name in COLUMNS}
    compared = 0
    statuses = {}
    histogram = {}  # altitude error by decade: count of samples with 10^e <= |diff| < 10^(e+1)
    for d, q, i in zip(double_lines, quad_lines, input_lines):
        dt, qt = d.split(), q.split()
        if dt[0] != qt[0]:
            raise SystemExit(f"status differs between builds: {d} / {q}")
        statuses[dt[0]] = statuses.get(dt[0], 0) + 1
        if dt[0] != "0":
            continue
        compared += 1
        for k, name in enumerate(COLUMNS, start=1):
            diff = abs(Decimal(float.fromhex(dt[k])) - Decimal(qt[k]))
            if name in PERIOD:
                diff = min(diff, abs(diff - PERIOD[name]))
            if diff > worst[name][0]:
                worst[name] = (diff, i)
            if name == "altitude_deg":
                decade = "0" if diff == 0 else str(diff.adjusted())
                histogram[decade] = histogram.get(decade, 0) + 1
    return worst, compared, statuses, histogram


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--step", type=float, default=25.0, help="TT days between epochs (default 25; the article used 0.377)")
    parser.add_argument("--outside", action="store_true", help="sample the century on either side of the polynomial coverage instead")
    parser.add_argument("--check", action="store_true", help="fail when a column exceeds its ceiling in bounds.json")
    parser.add_argument("--optimization", default="-O2", help="flag for the binary64 build (default -O2; write --optimization=-O0)")
    args = parser.parse_args()

    quad_cc = find_quad_compiler()
    if quad_cc is None:
        raise SystemExit("no compiler with libquadmath found; set QUAD_CC (for example QUAD_CC=gcc-15 with Homebrew GCC)")
    cc = os.environ.get("CC", "cc")
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        double_binary = compile_probe(cc, ENGINE, directory / "probe_double", ["-std=c11", args.optimization])
        quad_binary = build_quad(directory, quad_cc)
        inputs = grid(args.step, args.outside)
        input_lines = inputs.splitlines()
        worst, compared, statuses, histogram = compare(run(double_binary, inputs), run(quad_binary, inputs), input_lines)

    print(f"binary64 compiler: {cc} {args.optimization}; binary128 compiler: {quad_cc}")
    print(f"epochs: {len(input_lines) // len(OBSERVERS)}, observers: {len(OBSERVERS)}, compared: {compared}, statuses: {statuses}")
    for name in COLUMNS:
        diff, where = worst[name]
        print(f"{name:>16}: max |binary64 - binary128| = {diff:.3e}  at {where}")
    decades = sorted((k for k in histogram if k != "0"), key=int)
    print("altitude error by decade (count of samples with 1e<n> <= |diff| < 1e<n+1>):")
    print("  " + "  ".join(f"1e{d}: {histogram[d]}" for d in decades) + (f"  exact: {histogram['0']}" if "0" in histogram else ""))

    if args.check:
        ceilings = json.loads((HERE / "bounds.json").read_text())["measuredCeilings"]
        failures = [name for name, limit in ceilings.items() if worst[name][0] > Decimal(str(limit))]
        if failures:
            raise SystemExit(f"columns above their ceiling: {failures}")
        print("all columns within the ceilings in bounds.json")


if __name__ == "__main__":
    main()
