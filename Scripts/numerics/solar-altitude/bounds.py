#!/usr/bin/env python3
"""Exact-arithmetic bounds for the geometric solar altitude error budget.

Every number here is computed with Python fractions from the shipped
sources: the frozen Earth polynomial archive (through the verified loader in
Scripts/performance/polynomial/embed.py), the IAU2000B table, the constants
in astronomy.h and astronomy.c, and coefficients copied from named functions
in astronomy.c, each of which is asserted to still appear in that function.
The derivations are in the DocC article <doc:SolarAltitudeNumerics>.
`--write` records the results in bounds.json; `--check` (CI) recomputes them
and compares.
"""
import argparse
import json
import math
import re
import sys
from fractions import Fraction as F
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "Scripts/performance/polynomial"))
import embed  # noqa: E402

ENGINE = (ROOT / "Sources/CLibAstronomy/astronomy.c").read_text()
HEADER = (ROOT / "Sources/CLibAstronomy/include/astronomy.h").read_text()
NUTATION = ROOT / "Sources/CLibAstronomy/generated/iau2000b_full.h"
TARGET = HERE / "bounds.json"

START, STOP = F(embed.START), F(embed.STOP)  # polynomial coverage, TT days from J2000
CENTURIES = F("1.01")  # Julian centuries from J2000 spanned by the coverage, rounded outward
U = F(1, 2**53)  # binary64 unit roundoff
DEG = 180 / F(math.pi)
ASEC_PER_DEG = 3600
DAYS_PER_CENTURY = 36525
OBSERVER_HEIGHT_KM = F(10)  # the budget covers observers up to 10 km above the ellipsoid


def header_constant(name):
    """A #define from astronomy.h, as the exact value of its decimal literal."""
    return F(re.search(rf"#define\s+{name}\s+([-+0-9.eE]+)", HEADER).group(1))


def engine_constant(name):
    """A `static const double` from astronomy.c, as the exact value of its literal."""
    return F(re.search(rf"static const double {name} = ([-+0-9.eE]+);", ENGINE).group(1))


def engine_function(name):
    """The body of a function in astronomy.c, by brace matching."""
    # A definition line may end in a comment, as era() does.
    start = re.search(rf"^[\w\s\*]*\b{name}\s*\([^;]*\)[^\n;]*\n\{{", ENGINE, re.MULTILINE).start()
    depth = 0
    for i in range(ENGINE.index("{", start), len(ENGINE)):
        depth += {"{": 1, "}": -1}.get(ENGINE[i], 0)
        if depth == 0:
            return ENGINE[start:i + 1]
    raise ValueError(name)


def literals(function, texts):
    """Fractions for literals copied from `function`, after checking they are still there."""
    body = engine_function(function)
    # The engine writes negative terms as "- 0.0598939*u2"; check the digits, keep the sign.
    missing = [t for t in texts if t.lstrip("-+") not in body]
    if missing:
        raise ValueError(f"{function} no longer contains {missing}; update bounds.py")
    return [F(t) for t in texts]


def polynomial_derivative_bound(coefficients, t_max):
    """max |d/dt sum c_k t^k| over |t| <= t_max."""
    return sum(k * abs(c) * t_max ** (k - 1) for k, c in enumerate(coefficients) if k > 0)


def polynomial_bounds():
    """Speed, radius, and join-discontinuity bounds from the Earth archive."""
    row = next(r for r in embed.manifest() if r["body"] == "Earth")
    coefficients, valid = embed.load_body(row)
    degree, width, count = row["degree"], row["width"], row["segments"]
    if not all(valid):
        raise ValueError("an Earth segment is excluded; the bounds assume the polynomial path everywhere")
    n = degree + 1
    half = F(width, 2)
    grid = [F(-1) + F(2 * i, width) for i in range(width)]  # one-day spacing in x

    def clenshaw(a, x):
        b1 = b2 = F(0)
        for k in range(degree, 0, -1):
            b1, b2 = 2 * x * b1 - b2 + a[k], b1
        return x * b1 - b2 + a[0]

    # |T_k'(x)| <= k^2 on [-1, 1] and dx/dtt = 1/half, so each velocity axis is
    # bounded by (sum k^2 |a_k|) / half; the speed by the norm of the three.
    speed2 = F(0)
    ends = []
    radius2_min = None
    for s in range(count):
        axes = [[F(c) for c in coefficients[(s * 3 + axis) * n:(s * 3 + axis + 1) * n]] for axis in range(3)]
        speed2 = max(speed2, sum((sum(k * k * abs(a[k]) for k in range(1, n)) / half) ** 2 for a in axes))
        ends.append(([sum(a[k] * (-1) ** k for k in range(n)) for a in axes], [sum(a) for a in axes]))
        for x in grid:
            r2 = sum(clenshaw(a, x) ** 2 for a in axes)
            radius2_min = r2 if radius2_min is None else min(radius2_min, r2)
    speed = F(math.sqrt(speed2)) * (1 + F(1, 10**12))  # float sqrt, rounded up
    assert speed * speed >= speed2
    radius_grid = F(math.sqrt(radius2_min)) * (1 - F(1, 10**12))  # rounded down
    assert radius_grid * radius_grid <= radius2_min
    jumps = [max(abs(ends[s][1][axis] - ends[s + 1][0][axis]) for axis in range(3)) for s in range(count - 1)]
    return {
        "segments": count,
        "speedAUPerDay": speed,
        "radiusAU": radius_grid - speed / 2,  # widened by half the grid spacing
        "joinMaxAU": max(jumps),
        "joinSumAU": sum(jumps),
    }


def frame_rate_bounds():
    """Angular rates of everything that reads TT, in degrees per TT day."""
    per_day = F(1, ASEC_PER_DEG * DAYS_PER_CENTURY)  # arcsec per century to degrees per day
    # precession_rot: psiA, omegaA, chiA in arcsec as polynomials in t (centuries).
    psi = [F(0)] + literals("precession_rot", ["5038.481507", "1.0790069", "0.00114045", "0.000132851", "0.0000000951"])
    omega = literals("precession_rot", ["84381.406", "0.025754", "0.0512623", "0.00772503", "0.000000467", "0.0000003337"])
    chi = [F(0)] + literals("precession_rot", ["10.556403", "2.3814292", "0.00121197", "0.000170663", "0.0000000560"])
    precession = sum(polynomial_derivative_bound(p, CENTURIES) for p in (psi, omega, chi))
    obliquity = polynomial_derivative_bound(
        literals("mean_obliq", ["84381.406", "46.836769", "0.0001831", "0.00200340", "0.000000576", "0.0000000434"]), CENTURIES)
    sidereal = polynomial_derivative_bound(
        literals("Astronomy_SiderealTime", ["0.014506", "4612.156534", "1.3915817", "0.00000044", "0.000029956", "0.0000000368"]), CENTURIES)
    # IAU2000B: dpsi = sum (c0 + c1 t) sin(arg) + c2 cos(arg) and deps likewise
    # with c3, c4, c5, in 1e-7 arcsec; arg = sum n_j args_j with these rates.
    rates = literals("iau2000b_eval", ["1717915923.2178", "129596581.0481", "1739527262.8478", "1602961601.2090", "-6962890.5431"])
    asec2rad = F(math.pi) / (180 * 3600)
    terms = re.findall(r"\{\s*\{([^{}]*)\}\s*,\s*\{([^{}]*)\}\s*\}", NUTATION.read_text())
    if len(terms) != 77:
        raise ValueError(f"expected 77 IAU2000B terms, found {len(terms)}")
    dpsi = deps = F(0)
    for n_text, c_text in terms:
        n = [F(v) for v in n_text.split(",")]
        c = [F(v) for v in c_text.split(",")]
        argdot = abs(sum(nj * rj for nj, rj in zip(n, rates))) * asec2rad  # rad per century
        dpsi += abs(c[1]) + (abs(c[0]) + abs(c[1]) * CENTURIES) * argdot + abs(c[2]) * argdot
        deps += abs(c[4]) + (abs(c[3]) + abs(c[4]) * CENTURIES) * argdot + abs(c[5]) * argdot
    nutation = (dpsi + deps) / 10**7
    equinoxes = dpsi / 10**7  # sidereal time also carries dpsi cos(eps)
    rates = {
        "precessionDegPerDay": precession * per_day,
        "obliquityDegPerDay": obliquity * per_day,
        "siderealPolynomialDegPerDay": sidereal * per_day,
        "nutationDegPerDay": nutation * per_day,
        "equinoxesDegPerDay": equinoxes * per_day,
    }
    rates["ttSensitivityDegPerDay"] = sum(rates.values())
    return rates


def delta_t_slope_bound():
    """|d DeltaT / d ut| over the coverage span, seconds per day.

    Astronomy_DeltaT_EspenakMeeus is piecewise polynomial in u, a shifted
    year. For each piece that meets the years 1900 to 2101, the derivative
    is bounded by sum k |c_k| max|u|^(k-1) over the piece's u range.
    """
    function = "Astronomy_DeltaT_EspenakMeeus"
    pieces = [
        # (coefficient literals in u, largest |u| on the piece)
        (["-2.79", "1.494119", "-0.0598939", "0.0061966", "-0.000197"], 20),
        (["21.20", "0.84493", "-0.076100", "0.0020936"], 21),
        (["29.07", "0.407", "233", "2547"], 11),  # u^2/233 and u^3/2547
        (["45.45", "1.067", "260", "718"], 14),  # u^2/260 and u^3/718
        (["63.86", "0.3345", "-0.060374", "0.0017275", "0.000651814", "0.00002373599"], 14),
        (["62.92", "0.32217", "0.005589"], 50),
    ]
    slope = F(0)
    for texts, u_max in pieces:
        values = literals(function, texts)
        if texts[2] in ("233", "260"):
            values = [values[0], values[1], 1 / values[2], 1 / values[3]]
        slope = max(slope, polynomial_derivative_bound(values, F(u_max)))
    # 2050 to 2150: -20 + 32 u^2 - 0.5628 (2150 - y), u = (y - 1820)/100, so
    # d/dy = 0.64 u + 0.5628, largest at y = 2101.
    slope = max(slope, F(64, 100) * (F(2101) - 1820) / 100 + literals(function, ["0.5628"])[0])
    return slope / engine_constant("DAYS_PER_TROPICAL_YEAR")


def compute():
    earth = polynomial_bounds()
    frame = frame_rate_bounds()
    speed, radius = earth["speedAUPerDay"], earth["radiusAU"]
    slope = delta_t_slope_bound()
    tt_per_ut = 1 + slope / 86400  # Astronomy_AddDays derives TT from UT

    # Civil UTC to TT (CivilTime.terrestrialTime, Swift): five binary64 operations
    # with the standard model of floating-point arithmetic.
    offset_max = F("69.184") + F("0.9")  # largest table offset plus rate times span
    civil_tt_days = 2 * U * STOP + 3 * U * offset_max / 86400
    # TT to UT inverse (Astronomy_TerrestrialTimeWithDeltaT): the tolerance in the code.
    inverse_days = max(F(1, 10**12), 2 * U * STOP)
    # Earth Rotation Angle (era): thet1 = offset + rate * ut and thet1 + fmod(ut, 1)
    # round three times at up to |thet1| + 1 revolutions; fmod is exact; the
    # final product by 360 rounds once more below one revolution.
    era_offset, era_rate = literals("era", ["0.7790572732640", "0.00273781191135448"])
    era_deg = 4 * U * (era_offset + era_rate * STOP + 1) * 360
    # Light-time termination: contraction constant k = v/c; the loop stops when
    # two successive backdated TT values, each rounded at ulp(|tt|), differ by
    # less than 1e-9 day, so the exact step can exceed that by 4 u |tt|.
    k = speed / header_constant("C_AUDAY")
    light_time_days = (F(1, 10**9) + 4 * U * STOP) / (1 - k)
    light_time_deg = speed * light_time_days * tt_per_ut / radius * DEG
    # Sensitivities, degrees per day of each input scale. era() advances
    # 1 + rate revolutions per UT day; |d altitude / d hour angle| <= cos(latitude) <= 1.
    sun_rate = speed * (1 + k / (1 - k)) / radius * DEG
    observer_au = (header_constant("EARTH_EQUATORIAL_RADIUS_KM") + OBSERVER_HEIGHT_KM) / header_constant("KM_PER_AU")
    parallax_rate = 2 * F(math.pi) * observer_au / radius * DEG
    ut_sensitivity = (1 + era_rate) * 360 + sun_rate * tt_per_ut + parallax_rate
    tt_sensitivity = frame["ttSensitivityDegPerDay"]
    return {
        "earth": {key: (value if isinstance(value, int) else float(value)) for key, value in earth.items()},
        "frameRates": {key: float(value) for key, value in frame.items()},
        "deltaTSlopeSecondsPerDay": float(slope),
        "civilToTTDays": float(civil_tt_days),
        "civilToTTDegrees": float(civil_tt_days * tt_sensitivity),
        "ttInverseDays": float(inverse_days),
        "ttInverseDegrees": float(inverse_days * ut_sensitivity),
        "eraDegrees": float(era_deg),
        "lightTimeDays": float(light_time_days),
        "lightTimeDegrees": float(light_time_deg),
        "sunRateDegPerDay": float(sun_rate),
        "utSensitivityDegPerDay": float(ut_sensitivity),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="record the bounds in bounds.json")
    parser.add_argument("--check", action="store_true", help="verify bounds.json against the sources")
    args = parser.parse_args()
    computed = compute()
    existing = json.loads(TARGET.read_text()) if TARGET.exists() else {}
    if args.write:
        # The ceilings are review decisions for measure.py --check, not computed values.
        document = {"computed": computed, "measuredCeilings": existing.get("measuredCeilings", {})}
        TARGET.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
        print(f"wrote {TARGET.relative_to(ROOT)}")
    elif args.check:
        if existing.get("computed") != computed:
            raise SystemExit("bounds.json is stale; run bounds.py --write and review the article")
        print("bounds.json matches the sources")
    else:
        print(json.dumps(computed, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
