#!/usr/bin/env python3
"""Attribute residual differences without changing production or frozen references.

Requires pyswisseph==2.10.3.2 in a separate diagnostic environment. Swiss is
never imported by the shipping library. A common-TT comparison evaluates Swiss
at Astronomy Engine's TT, including at each derivative sample; it does not
overwrite just the reception time of a light-travel calculation.
"""
import argparse
import ctypes
import datetime as dt
import hashlib
import importlib.metadata
import json
from pathlib import Path

import swisseph as swe

from measure import BODIES, EPOCH, Model, fixtures, refine, signed

FLAGS = swe.FLG_MOSEPH | swe.FLG_SPEED
SWISS = {name: getattr(swe, name.upper()) for name in BODIES if name != "earth"}
MODES = {
    "apparent": (0, FLAGS),
    "lightTimeOnly": (1, FLAGS | swe.FLG_NOABERR | swe.FLG_NOGDEFL),
    "geometric": (2, FLAGS | swe.FLG_TRUEPOS | swe.FLG_NOABERR | swe.FLG_NOGDEFL),
    "heliocentric": (3, FLAGS | swe.FLG_HELCTR | swe.FLG_TRUEPOS | swe.FLG_NOABERR | swe.FLG_NOGDEFL),
}


def swiss(body, days, flags, common_tt):
    values, returned = (swe.calc if common_tt else swe.calc_ut)(days+2451545.0, SWISS[body], flags)
    if returned & (swe.FLG_MOSEPH | swe.FLG_SWIEPH | swe.FLG_JPLEPH) != swe.FLG_MOSEPH:
        raise ValueError("Swiss unexpectedly changed ephemeris model")
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if importlib.metadata.version("pyswisseph") != "2.10.3.2":
        raise SystemExit("Exactly pyswisseph==2.10.3.2 is required")
    model = Model(args.library.resolve())
    fn = model.library.ak_components
    fn.argtypes = [ctypes.c_int, ctypes.c_double, ctypes.c_int, ctypes.POINTER(ctypes.c_double)]
    fn.restype = ctypes.c_int

    def native(body, at, mode):
        result = (ctypes.c_double*3)()
        if fn(BODIES.index(body), at, mode, result):
            raise ValueError("Native component sample unavailable")
        return list(result)

    rows = []
    for case, oracle in fixtures():
        for index, event in enumerate(oracle["events"]):
            bodies = event.get("bodies", [])
            if not bodies:
                continue
            at = (dt.datetime.fromisoformat(event["instant"])-EPOCH).total_seconds()/86400
            tt = model.position(bodies[0], at)[2]
            row = {"caseID": case, "eventIndex": index, "identity": event,
                   "deltaTNativeSeconds": (tt-at)*86400,
                   "deltaTSwissSeconds": swe.deltat_ex(at+2451545, swe.FLG_MOSEPH)*86400,
                   "bodies": {}}
            for body in bodies:
                measured = {}
                for name, (mode, flags) in MODES.items():
                    if name == "heliocentric" and body in {"sun", "moon"}:
                        continue
                    lon, lat, sample_tt = native(body, at, mode)
                    r = swiss(body, sample_tt, flags, True)
                    width = .0007
                    before = native(body, at-width/2, mode)
                    after = native(body, at+width/2, mode)
                    speed = signed(after[0]-before[0])/width
                    rspeed = signed(swiss(body, after[2], flags, True)[0]
                                    - swiss(body, before[2], flags, True)[0])/width
                    measured[name] = {"commonTTLongitudeErrorArcseconds": signed(lon-r[0])*3600,
                                      "commonTTLatitudeErrorArcseconds": (lat-r[1])*3600,
                                      "commonTTSpeedFiniteDifferenceErrorDegreesPerDay": speed-rspeed,
                                      "commonTTSpeedReturnedErrorDegreesPerDay": speed-r[3]}
                production = model.position(body, at)
                r = swiss(body, tt, FLAGS, True)
                measured["dedicatedProductionPath"] = {
                    "commonTTLongitudeErrorArcseconds": signed(production[0]-r[0])*3600,
                    "commonTTLatitudeErrorArcseconds": (production[1]-r[1])*3600}
                row["bodies"][body] = measured
            if event["kind"] == "station":
                body = bodies[0]
                comparisons = {}
                for name, (mode, flags) in list(MODES.items())[:3]:
                    def velocity(offset, reference=False, common_tt=False):
                        a = at + offset/86400
                        if reference:
                            epoch = model.position(body, a)[2] if common_tt else a
                            # The frozen stations use Swiss's returned SPEED value.
                            # A numerical derivative of Swiss positions is a separate diagnostic.
                            return swiss(body, epoch, flags, common_tt)[3]
                        before = native(body, a-.00035, mode)
                        after = native(body, a+.00035, mode)
                        before_lon, after_lon = before[0], after[0]
                        return signed(after_lon-before_lon)/.0007
                    n = refine(velocity)[0]
                    common = refine(lambda s: velocity(s, True, True))[0]
                    universal = refine(lambda s: velocity(s, True, False))[0]
                    comparisons[name] = {"nativeOffsetSeconds": n, "swissNativeUTOffsetSeconds": universal,
                                         "swissCommonTTOffsetSeconds": common,
                                         "nativeMinusSwissCommonTTSeconds": n-common}
                row["stationComponents"] = comparisons
                # Returned SPEED defines the frozen references. Expose its distinction
                # from differentiated longitudes; do not replace the reference with these roots.
                row["swissLongitudeDifferenceRootsSeconds"] = {}
                for width in (.00035, .0007, .0014, .007, .014, .07, .14):
                    def difference(offset):
                        a = at + offset/86400
                        return signed(swiss(body, a+width/2, FLAGS, False)[0]
                                      - swiss(body, a-width/2, FLAGS, False)[0])/width
                    row["swissLongitudeDifferenceRootsSeconds"][str(width)] = refine(difference)[0]
            rows.append(row)
    report = {"oraclePackage": "pyswisseph==2.10.3.2", "oracleLibraryVersion": swe.version,
              "oracleBinarySHA256": hashlib.sha256(Path(swe.__file__).read_bytes()).hexdigest(),
              "nativeLibrarySHA256": hashlib.sha256(args.library.read_bytes()).hexdigest(),
              "purpose": "Residual attribution, not reference replacement or new acceptance tolerances",
              "results": rows}
    args.output.write_text(json.dumps(report, indent=2)+"\n")
    for row in rows:
        if row["caseID"] == "A11":
            print(json.dumps(row, indent=2))


if __name__ == "__main__":
    main()
