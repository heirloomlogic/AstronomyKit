#!/usr/bin/env python3
"""Writes the seed corpus for Fuzzing/fuzz_bridge.c.

Each seed encodes one set of harness fields in the input format decoded by
fuzz_bridge.c. The times, bodies, observers, and coordinates come from the
package's reference tests (JPLValidationTests, AuditValidationTests,
RiseSetTests, FixedStarTests, RotationTests), plus a few seeds at the edges the
engine guards: the Pluto table and crawl limits, a polar observer, and
non-finite values.

    python3 Fuzzing/make_corpus.py          # rewrite Fuzzing/corpus/
    python3 Fuzzing/make_corpus.py --check  # fail if Fuzzing/corpus/ is stale
"""

import argparse
import math
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

CORPUS = Path(__file__).resolve().parent / "corpus"

# The start of BodyValues in fuzz_bridge.c; a body's index is its byte.
BODIES = ("mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus",
          "neptune", "pluto", "sun", "moon", "emb", "ssb", "star1", "star2")

J2000 = datetime(2000, 1, 1, 12, tzinfo=timezone.utc)


def ut_days(year, month, day, hour=0, minute=0, second=0.0):
    """Days from J2000 (2000-01-01 12:00 UTC) to a UTC calendar time."""
    moment = datetime(year, month, day, hour, minute, tzinfo=timezone.utc)
    return ((moment - J2000).total_seconds() + second) / 86400.0


def ra_hours(h, m, s):
    return h + m / 60.0 + s / 3600.0


def dec_degrees(d, m, s):
    value = abs(d) + m / 60.0 + s / 3600.0
    return -value if d < 0 else value


def double(value):
    """Tag 0: the raw little-endian IEEE 754 bits."""
    return b"\x00" + struct.pack("<d", value)


def enum(choice):
    """Choice 0 or 1 selects the first or second valid value of the enum."""
    return bytes([choice])


IDENTITY = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
ALGOL = (3.136148, 40.9556, 92.95)      # FixedStarTests: RA hours, Dec degrees, light-years
JPL_DATE = ut_days(2026, 1, 2)          # first reference date in every JPLValidationTests suite


def seed(
    body,
    time,
    observer=(0.0, 0.0, 0.0),
    star=ALGOL,
    terrestrial=False,
    jpl_delta_t=False,
    aberration=0,
    equator_date=0,
    constellation=(0.0, 0.0),
    rotation=IDENTITY,
    axis=0,
    angle=30.0,
    direction=0,
    limit_days=366.0,
    meters_above_ground=0.0,
):
    """Encodes fields in the order LLVMFuzzerTestOneInput reads them."""
    flags = (1 if terrestrial else 0) | (2 if jpl_delta_t else 0)
    out = bytes([flags])
    out += b"".join(double(v) for v in star)
    out += double(time)
    out += bytes([BODIES.index(body)])
    out += b"".join(double(v) for v in observer)
    out += enum(aberration)                              # GeoVector
    out += enum(equator_date) + enum(aberration)         # Equator
    out += b"".join(double(v) for v in constellation)
    out += bytes([0])                                    # rotation status: success
    out += b"".join(double(v) for v in rotation)
    out += bytes([axis]) + double(angle)
    out += enum(direction) + double(limit_days) + double(meters_above_ground)
    return out


GEOCENTER = (0.0, 0.0, -6378137.0)      # Observer.geocentric
PRIME = (0.0, 0.0, 0.0)                 # Observer.primeMeridian, so rise/set runs
ASHEVILLE = (35.595, -82.5572, 0.0)     # JPLValidationTests
AUDIT = (35.5951, -82.5515, 0.0)        # AuditValidationTests
NYC = (40.7128, -74.0060, 0.0)          # RiseSetTests
LONDON = (51.5074, -0.1278, 0.0)        # RiseSetTests

SEEDS = {
    # JPLValidationTests: the first reference date of each geocentric suite. The
    # Sun and Moon keep the geocentric observer and use the JPL right ascension
    # and declination for the constellation lookup; the planets use the prime
    # meridian so the rise/set search runs instead of rejecting the observer.
    "jpl-sun": seed("sun", JPL_DATE, GEOCENTER,
                    constellation=(ra_hours(18, 48, 50.13), dec_degrees(-22, 57, 40.4))),
    "jpl-moon": seed("moon", JPL_DATE, GEOCENTER, equator_date=1,
                     constellation=(ra_hours(5, 21, 1.61), dec_degrees(28, 7, 0.3))),
    "jpl-mercury": seed("mercury", JPL_DATE, PRIME, aberration=1),
    "jpl-venus": seed("venus", JPL_DATE, PRIME, jpl_delta_t=True),
    "jpl-mars": seed("mars", JPL_DATE, PRIME, axis=1),
    "jpl-jupiter": seed("jupiter", JPL_DATE, PRIME, axis=2, angle=-90.0),
    "jpl-saturn": seed("saturn", JPL_DATE, PRIME, direction=1),
    "jpl-uranus": seed("uranus", JPL_DATE, PRIME, terrestrial=True),
    "jpl-neptune": seed("neptune", JPL_DATE, PRIME, limit_days=-366.0),
    "jpl-pluto": seed("pluto", JPL_DATE, PRIME),
    # JPLValidationTests: Asheville topocentric Moon.
    "jpl-asheville-moon": seed("moon", JPL_DATE, ASHEVILLE, equator_date=1,
                               constellation=(ra_hours(5, 24, 20.98), dec_degrees(27, 46, 49.7))),
    # AuditValidationTests: the audit instant and observer.
    "audit-sun": seed("sun", ut_days(2026, 1, 1, 20, 4, 19.891), AUDIT, equator_date=1),
    "audit-moon": seed("moon", ut_days(2026, 1, 1, 20, 4, 19.891), AUDIT, jpl_delta_t=True),
    # RiseSetTests: sunrise and moonrise over a year-long window.
    "riseset-nyc-sun": seed("sun", ut_days(2025, 6, 21), NYC),
    "riseset-london-moon": seed("moon", ut_days(2025, 6, 21), LONDON, direction=1),
    # FixedStarTests: Algol as user-defined star 1; star 2 stays undefined.
    "fixedstar-algol": seed("star1", JPL_DATE, ASHEVILLE, equator_date=1,
                            constellation=ALGOL[:2]),
    "fixedstar-undefined": seed("star2", JPL_DATE, ASHEVILLE),
    # Edges the engine guards: the Pluto state table ends and crawl limits
    # (PLUTO_MAX_CRAWL_DAYS), a polar summer, and non-finite values.
    "edge-pluto-table-start": seed("pluto", -730000.0, terrestrial=True, limit_days=1.0),
    "edge-pluto-crawl-limit": seed("pluto", 766525.0, terrestrial=True, limit_days=1.0),
    "edge-polar-sun": seed("sun", ut_days(2025, 6, 21), (89.9, 0.0, 0.0)),
    "edge-nonfinite": seed("earth", math.inf, (math.nan, math.inf, -math.inf),
                           star=(math.nan, math.inf, -math.inf), constellation=(math.nan, math.inf),
                           rotation=(math.nan,) * 9, angle=math.inf, limit_days=0.0,
                           meters_above_ground=math.nan),
    # Fixed findings. Each hung or hit undefined behavior before the extreme-input
    # guards (MAINTAINING.md, patch 15).
    # #57: a window that runs into 2^52 days, where the 0.42-day step stops
    # advancing. The start alone steps normally. Libration hung here too.
    "fixed-riseset-stall": seed("moon", 2.0**52 - 3.0, PRIME, limit_days=10.0),
    # #57: an infinite limit for a circumpolar star, which never rises.
    "fixed-riseset-infinite-limit": seed("star1", JPL_DATE, (80.0, 0.0, 0.0), star=(0.0, 89.0, 1000.0),
                                         limit_days=math.inf),
    # #58: Pluto at a NaN time, which also reaches the Moon node and Pluto apsis searches.
    "fixed-pluto-nan": seed("pluto", math.nan, PRIME),
    # Longitude searches for a target angle far outside 0-360.
    "fixed-longitude-huge-target": seed("mars", JPL_DATE, PRIME, angle=1.0e20),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if Fuzzing/corpus is stale")
    check = parser.parse_args().check

    actual = {p.name: p.read_bytes() for p in CORPUS.glob("*")} if CORPUS.is_dir() else {}

    if check:
        stale = sorted(name for name in set(actual) | set(SEEDS) if actual.get(name) != SEEDS.get(name))
        if stale:
            sys.exit("Fuzzing/corpus is stale; run python3 Fuzzing/make_corpus.py (" + ", ".join(stale) + ")")
        print(f"Fuzzing/corpus is current ({len(SEEDS)} seeds).")
        return

    CORPUS.mkdir(exist_ok=True)
    for name in set(actual) - set(SEEDS):
        (CORPUS / name).unlink()
    for name, data in SEEDS.items():
        (CORPUS / name).write_bytes(data)
    print(f"Wrote {len(SEEDS)} seeds to Fuzzing/corpus.")


if __name__ == "__main__":
    main()
