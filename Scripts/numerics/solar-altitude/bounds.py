#!/usr/bin/env python3
"""Exact-arithmetic bounds for the geometric solar altitude error budget.

Every number here is computed with Python fractions from the shipped
sources: the frozen Earth polynomial archive (through the verified loader in
Scripts/performance/polynomial/embed.py), the IAU2000B table, the constants
in astronomy.h and astronomy.c, the civil offset table in
UTCOffsetTable.swift, and coefficients copied from named functions in
astronomy.c, each of which is asserted to still appear in that function.
Rounding follows the standard model of floating-point arithmetic: every
binary64 operation returns its exact result times (1 + d) with |d| <= u.
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
CIVIL_TABLE = (ROOT / "Sources/AstronomyKit/UTCOffsetTable.swift").read_text()
TIME_SWIFT = (ROOT / "Sources/AstronomyKit/Time.swift").read_text()
TARGET = HERE / "bounds.json"

START, STOP = F(embed.START), F(embed.STOP)  # polynomial coverage, TT days from J2000
CENTURIES = F("1.01")  # Julian centuries from J2000 spanned by the coverage, rounded outward
U = F(1, 2**53)  # binary64 unit roundoff
EPSILON = 2 * U  # DBL_EPSILON
DEG = 180 / F(math.pi)
ASEC_PER_DEG = 3600
DAYS_PER_CENTURY = 36525
SECONDS_PER_DAY = 86400
OBSERVER_HEIGHT_KM = F(10)  # the budget covers observers up to 10 km above the ellipsoid
DELTA_T = "Astronomy_DeltaT_EspenakMeeus"


def header_constant(name):
    """A #define from astronomy.h, as the exact value of its decimal literal."""
    return F(re.search(rf"#define\s+{name}\s+([-+0-9.eE]+)", HEADER).group(1))


def engine_constant(name):
    """A `static const double` from astronomy.c, as the exact value of its literal."""
    return F(re.search(rf"static const double {name} = ([-+0-9.eE]+);", ENGINE).group(1))


def swift_constant(name):
    """A `static let` literal from Time.swift, as the exact value of its decimal literal."""
    match = re.search(rf"static let {name} = ([-+0-9_.eE]+)", TIME_SWIFT)
    if match is None:
        raise ValueError(f"Time.swift no longer defines {name}; update bounds.py")
    return F(match.group(1).replace("_", ""))


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


def expression(function, text):
    """Check that an expression is still written as `text` in `function`."""
    if text not in engine_function(function):
        raise ValueError(f"{function} no longer contains {text!r}; update bounds.py")


def rounded(magnitude, error=F(0)):
    """One binary64 operation under the standard model.

    The exact result of the operation has magnitude at most `magnitude` and is
    already within `error` of the value it stands for; the stored result is
    within u of that exact result. Returns the new magnitude and error bounds.
    """
    return magnitude * (1 + U), error + U * magnitude


def root_above(square):
    """A rational at or above the square root of `square`."""
    root = F(math.sqrt(square)) * (1 + F(1, 10**12))
    assert root * root >= square
    return root


def root_below(square):
    """A rational at or below the square root of `square`."""
    root = F(math.sqrt(square)) * (1 - F(1, 10**12))
    assert root * root <= square
    return root


def polynomial_derivative_bound(coefficients, t_max):
    """max |d/dt sum c_k t^k| over |t| <= t_max."""
    return sum(k * abs(c) * t_max ** (k - 1) for k, c in enumerate(coefficients) if k > 0)


def derivative(coefficients):
    return [k * c for k, c in enumerate(coefficients) if k > 0]


def evaluate(coefficients, u):
    return sum(c * u ** k for k, c in enumerate(coefficients))


def polynomial_range_bound(coefficients, low, high):
    """max |sum c_k u^k| over low <= u <= high.

    On each subinterval of width at most 1 the polynomial is expanded about the
    midpoint, p(c + h) = sum q_j h^j, and bounded by sum |q_j| |h|^j.
    """
    bound = F(0)
    a = F(low)
    while a < high:
        b = min(a + 1, F(high))
        center, half = (a + b) / 2, (b - a) / 2
        shifted = [sum(c * math.comb(k, j) * center ** (k - j) for k, c in enumerate(coefficients) if k >= j) for j in range(len(coefficients))]
        bound = max(bound, sum(abs(q) * half ** j for j, q in enumerate(shifted)))
        a = b
    return bound


def polynomial_bounds():
    """Speed, radius, and join-discontinuity bounds from the Earth archive."""
    row = next(r for r in embed.manifest() if r["body"] == "Earth")
    coefficients, valid = embed.load_body(row)
    degree, width, count = row["degree"], row["width"], row["segments"]
    if not all(valid):
        raise ValueError("an Earth segment is excluded; the bounds assume the polynomial path everywhere")
    n = degree + 1
    half = F(width, 2)
    grid = [F(-1) + F(2 * i, width) for i in range(width + 1)]  # one-day spacing in x, both ends

    def clenshaw(a, x):
        b1 = b2 = F(0)
        for k in range(degree, 0, -1):
            b1, b2 = 2 * x * b1 - b2 + a[k], b1
        return x * b1 - b2 + a[0]

    # |T_k'(x)| <= k^2 on [-1, 1] and dx/dtt = 1/half, so each velocity axis is
    # bounded by (sum k^2 |a_k|) / half; the speed by the norm of the three.
    speed2 = F(0)
    ends = []
    radius2_min = radius2_max = None
    for s in range(count):
        axes = [[F(c) for c in coefficients[(s * 3 + axis) * n:(s * 3 + axis + 1) * n]] for axis in range(3)]
        speed2 = max(speed2, sum((sum(k * k * abs(a[k]) for k in range(1, n)) / half) ** 2 for a in axes))
        ends.append(([sum(a[k] * (-1) ** k for k in range(n)) for a in axes], [sum(a) for a in axes]))
        for x in grid:
            r2 = sum(clenshaw(a, x) ** 2 for a in axes)
            radius2_min = r2 if radius2_min is None else min(radius2_min, r2)
            radius2_max = r2 if radius2_max is None else max(radius2_max, r2)
    speed = root_above(speed2)
    radius_grid = root_below(radius2_min)
    # A boundary jump is the vector difference between the end of one segment
    # and the start of the next; the direction bound needs its length.
    jumps = [root_above(sum((ends[s][1][axis] - ends[s + 1][0][axis]) ** 2 for axis in range(3))) for s in range(count - 1)]
    # The grid holds both ends of every segment, so every instant is within
    # half a day of a grid point of its own segment.
    return {
        "segments": count,
        "speedAUPerDay": speed,
        "radiusGridAU": radius_grid,
        "radiusAU": radius_grid - speed / 2,
        "radiusMaxAU": root_above(radius2_max) + speed / 2,
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


def delta_t_pieces():
    """The pieces of Astronomy_DeltaT_EspenakMeeus from 1860 on.

    Each is (first year, last year, shift, scale, coefficients): Delta T in
    seconds is the polynomial in u = (y - shift) / scale for first <= y < last.
    Astronomy_DeltaT_JplHorizons evaluates the same pieces with `ut` clamped at
    the year 2017, so these bounds cover it as well.
    """
    body = engine_function(DELTA_T)

    def piece(first, last, shift, scale, terms):
        coefficients = []
        for term in terms:
            if isinstance(term, tuple):  # (text as written, exact value) for the divided terms
                text, value = term
                if text not in body:
                    raise ValueError(f"{DELTA_T} no longer contains {text!r}; update bounds.py")
                coefficients.append(value)
            else:
                coefficients.append(literals(DELTA_T, [term])[0])
        return (first, last, shift, scale, coefficients)

    expression(DELTA_T, "y = 2000 + ((ut - 14) / DAYS_PER_TROPICAL_YEAR);")
    expression(DELTA_T, "u = (y-1820)/100;\n        return -20 + 32*u*u - 0.5628*(2150 - y);")
    slope_2150 = literals(DELTA_T, ["0.5628"])[0]
    return [
        piece(1860, 1900, 1860, 1, ["7.62", "0.5737", "-0.251754", "0.01680668", "-0.0004473624", ("u5/233174", F(1, 233174))]),
        piece(1900, 1920, 1900, 1, ["-2.79", "1.494119", "-0.0598939", "0.0061966", "-0.000197"]),
        piece(1920, 1941, 1920, 1, ["21.20", "0.84493", "-0.076100", "0.0020936"]),
        piece(1941, 1961, 1950, 1, ["29.07", "0.407", ("- u2/233", F(-1, 233)), ("+ u3/2547", F(1, 2547))]),
        piece(1961, 1986, 1975, 1, ["45.45", "1.067", ("- u2/260", F(-1, 260)), ("- u3/718", F(-1, 718))]),
        piece(1986, 2005, 2000, 1, ["63.86", "0.3345", "-0.060374", "0.0017275", "0.000651814", "0.00002373599"]),
        piece(2005, 2050, 2000, 1, ["62.92", "0.32217", "0.005589"]),
        # -20 + 32 u^2 - 0.5628 (2150 - y) with y = 1820 + 100 u, as a polynomial in u.
        (2050, 2150, 1820, 100, [F(-20) - slope_2150 * (2150 - 1820), slope_2150 * 100, F(32)]),
    ]


def delta_t_bounds():
    """Delta T over the years the coverage can reach: slope, magnitude, and the jumps between pieces.

    The engine's year is 2000 + (ut - 14) / DAYS_PER_TROPICAL_YEAR, so the
    coverage starts inside the 1860 piece. One day either side of the coverage
    covers the UT of any TT inside it and the light-time backdating.
    """
    tropical = engine_constant("DAYS_PER_TROPICAL_YEAR")
    pieces = delta_t_pieces()
    y_low, y_high = (2000 + (START - 1 - 14) / tropical), (2000 + (STOP + 1 - 14) / tropical)
    if not (pieces[0][0] <= y_low and y_high <= pieces[-1][1]):
        raise ValueError("the Delta T pieces no longer span the coverage years")
    slope = magnitude = F(0)
    jumps = {}
    for i, (first, last, shift, scale, coefficients) in enumerate(pieces):
        if i and pieces[i - 1][1] != first:
            raise ValueError("the Delta T pieces are not contiguous")
        low, high = max(F(first), y_low), min(F(last), y_high)
        if low >= high:
            continue
        u_low, u_high = (low - shift) / scale, (high - shift) / scale
        slope = max(slope, polynomial_range_bound(derivative(coefficients), u_low, u_high) / scale)
        magnitude = max(magnitude, polynomial_range_bound(coefficients, u_low, u_high))
        if i and y_low < first < y_high:
            _, _, previous_shift, previous_scale, previous = pieces[i - 1]
            jumps[f"y{first}"] = evaluate(coefficients, F(first - shift, scale)) - evaluate(previous, F(first - previous_shift, previous_scale))
    return {"slopeSecondsPerDay": slope / tropical, "magnitudeSeconds": magnitude, "jumpSeconds": jumps}


def civil_segments():
    """(start, offset, rate) of each segment in UTCOffsetTable.swift, as exact literals."""
    rows = re.findall(r"Segment\(start: ([-+0-9.eE]+), offset: ([-+0-9.eE]+), rate: ([-+0-9.eE]+)\)", CIVIL_TABLE)
    if len(rows) < 2:
        raise ValueError("UTCOffsetTable.swift no longer holds the segment table; update bounds.py")
    return [tuple(F(text) for text in row) for row in rows]


def compute():
    earth = polynomial_bounds()
    frame = frame_rate_bounds()
    delta_t = delta_t_bounds()
    speed, radius = earth["speedAUPerDay"], earth["radiusAU"]
    slope = delta_t["slopeSecondsPerDay"]
    tt_per_ut = 1 + slope / SECONDS_PER_DAY  # |d tt / d ut| along the model, at most
    ut_per_tt = 1 / (1 - slope / SECONDS_PER_DAY)  # |d ut / d tt| along the model, at most
    delta_t_days = delta_t["magnitudeSeconds"] / SECONDS_PER_DAY
    c_auday = header_constant("C_AUDAY")
    backdate = earth["radiusMaxAU"] / c_auday  # the light-time loop never backdates further
    assert delta_t_days + backdate < 1, "the one-day margins in delta_t_bounds and UTC_MAX no longer hold"
    ut_max = STOP + delta_t_days  # |ut| of a time whose tt is inside the coverage
    utc_max = STOP + 1  # |utc| of a civil time whose tt is inside the coverage, with a day to spare

    # Forward TT (TimeFromDaysWithDeltaT): tt = fl(ut + fl(DeltaT(ut) / 86400)).
    def forward_rounding(ut_bound):
        magnitude, error = rounded(delta_t_days)
        magnitude, error = rounded(ut_bound + magnitude, error)
        return error
    forward_tt_days = forward_rounding(ut_max)

    # TT to UT inverse (Astronomy_TerrestrialTimeWithDeltaT): the loop accepts
    # |fl(tt - time.tt)| <= tolerance, so |tt - time.tt| <= tolerance / (1 - u), and
    # time.tt is within the forward rounding of ut + DeltaT(ut) / 86400. The model's
    # own UT for tt is then within that residual times ut_per_tt of the stored ut.
    match = re.search(r"tolerance = fmax\(([-+0-9.eE]+), ([-+0-9.eE]+) \* ([-+0-9.eE]+) \* fabs\(tt\)\);", ENGINE)
    if match is None:
        raise ValueError("the inverse tolerance expression moved; update bounds.py")
    floor, factor, epsilon = (F(text) for text in match.groups())
    if float(epsilon) != float(EPSILON):  # the literal is DBL_EPSILON once rounded to binary64
        raise ValueError("the inverse tolerance no longer uses DBL_EPSILON; update bounds.py")
    tolerance = max(floor, factor * EPSILON * STOP)
    inverse_days = (tolerance / (1 - U) + forward_rounding(ut_max)) * ut_per_tt

    # Calendar arithmetic. init(_:): Foundation's `timeIntervalSince1970` adds
    # the reference-date offset to the interval a Date stores, rounding at the
    # magnitude of the seconds since 1970; then (seconds - offset) / 86400,
    # two more operations.
    magnitude, error = rounded(utc_max + swift_constant("j2000UnixOffset") / SECONDS_PER_DAY)
    magnitude, error = rounded(utc_max + error, error)
    magnitude, date_days = rounded(magnitude, error)
    # init(year:...): Astronomy_MakeTime adds hour/24, minute/1440, second/86400
    # to the day number. For in-range components the three quotients sum to
    # under a day, so their roundings total at most u; then three sums round.
    magnitude, error = utc_max + 1, U
    for _ in range(3):
        magnitude, error = rounded(magnitude, error)
    calendar_days = max(date_days, error)

    # Civil UTC to TT (CivilTime.terrestrialTime): utc + (offset + rate * (utc - start)) / 86400,
    # with the offset and rate literals each rounded to binary64, for the segment
    # whose offset + rate * span is largest. The calendar error arrives through
    # the conversion's slope 1 + rate / 86400.
    civil_tt_days = F(0)
    segments = civil_segments()
    for i, (start, offset, rate) in enumerate(segments):
        magnitude = error = F(0)
        if rate:
            span = segments[i + 1][0] - start
            magnitude, error = rounded(span)
            magnitude, error = rounded(rate * magnitude, rate * error + U * rate * magnitude)
        magnitude, error = rounded(offset + magnitude, error + U * offset)
        magnitude, error = rounded(magnitude / SECONDS_PER_DAY, error / SECONDS_PER_DAY)
        magnitude, error = rounded(utc_max + magnitude, error)
        civil_tt_days = max(civil_tt_days, error + calendar_days * (1 + rate / SECONDS_PER_DAY))

    # Earth Rotation Angle (era): each literal rounds to binary64, then
    # thet1 = offset + rate * ut rounds twice, thet1 + fmod(ut, 1) once at up to
    # |thet1| + 1 revolutions, fmod is exact, the product by 360 rounds once
    # below one revolution, and a negative result has 360 added, rounding once more.
    era_offset, era_rate = literals("era", ["0.7790572732640", "0.00273781191135448"])
    expression("era", "if (theta < 0.0)\n        theta += 360.0;")
    offset_magnitude, offset_error = rounded(era_offset)
    rate_magnitude, rate_error = rounded(era_rate)
    magnitude, error = rounded(rate_magnitude * ut_max, rate_error * ut_max)
    magnitude, error = rounded(offset_magnitude + magnitude, offset_error + error)
    era_revolutions = magnitude + 1
    magnitude, error = rounded(era_revolutions, error)
    magnitude, error = rounded(F(360), 360 * error)
    magnitude, era_deg = rounded(F(360), error)

    # Light-time termination (Astronomy_CorrectLightTravel). The backdated time
    # is fl(ut - fl(distance / C_AUDAY)), so each realized step of the fixed-point
    # map carries the rounding of those two operations; the stop test compares
    # forward-rounded TT values, which can differ by less than 1e-9 day while
    # the UT values differ by up to lightTimeStepDays. The map tau -> |E(t - tau)| / c
    # is a contraction with constant k; each realized iterate also evaluates the
    # distance at the forward-rounded TT, which moves it by at most speed times
    # that rounding, and Astronomy_VectorLength rounds three squares, two sums,
    # and a square root, within (1 + u)^3 of the exact length. So the last tau
    # is within (step + rounding) / (1 - k) of the exact fixed point, and the
    # position returned, evaluated at the forward-rounded TT of that tau, is
    # within speed * (forward rounding + tt_per_ut * lightTimeDays) of the
    # exact one. The rounding of the Earth position itself enters the distance
    # too; it is measured, not derived, and left to the measured line.
    expression("Astronomy_CorrectLightTravel", "if (dt < 1.0e-9)")
    stop = F(1, 10**9)
    k = speed * tt_per_ut / c_auday
    length_rounding = ((1 + U) ** 3 - 1) * earth["radiusMaxAU"]
    magnitude, error = rounded(backdate, length_rounding / c_auday)
    magnitude, backdate_rounding = rounded(ut_max + magnitude, error)
    iterate_rounding = backdate_rounding + speed * forward_rounding(ut_max) / c_auday
    step_days = (stop / (1 - U) + 2 * forward_rounding(ut_max)) * ut_per_tt
    light_time_days = (step_days + iterate_rounding) / (1 - k)
    light_time_au = speed * (forward_rounding(ut_max) + tt_per_ut * light_time_days)

    def direction_degrees(distance_au):
        # A vector of length at least `radius` moved by `distance_au` turns by at
        # most asin(x), x = distance / radius, and asin(x) <= x / (1 - x^2).
        x = distance_au / radius
        return x / (1 - x * x) * DEG

    # Sensitivities, degrees per day of each input scale. era() advances
    # 1 + rate revolutions per UT day, and so does the observer about the axis;
    # |d altitude / d hour angle| <= cos(latitude) <= 1. The Sun's direction
    # moves at most speed / radius per day of backdated time, and the light-time
    # fixed point drifts with it by a factor 1 + k / (1 - k).
    sun_rate = speed * (1 + k / (1 - k)) / radius * DEG
    observer_au = (header_constant("EARTH_EQUATORIAL_RADIUS_KM") + OBSERVER_HEIGHT_KM) / header_constant("KM_PER_AU")
    parallax_rate = (1 + era_rate) * 2 * F(math.pi) * observer_au / radius * DEG
    ut_sensitivity = (1 + era_rate) * 360 + sun_rate * tt_per_ut + parallax_rate
    tt_sensitivity = frame["ttSensitivityDegPerDay"]
    # An error in one scale reaches the other through the model. From 1961 on
    # the civil tt seeds init(tt:), so the derived ut is off by the tt error
    # times ut_per_tt on top of the inverse term; before 1961 the civil ut seeds
    # the forward tt, off by the ut error times tt_per_ut on top of the forward
    # rounding. init(tt:) stores tt exactly, init(ut:) stores ut exactly, and
    # the pair initializer stores both, so those rows carry one scale only.
    civil_tt_degrees = civil_tt_days * (tt_sensitivity + ut_per_tt * ut_sensitivity)
    civil_ut_degrees = calendar_days * (ut_sensitivity + tt_per_ut * tt_sensitivity)
    return {
        "earth": {key: (value if isinstance(value, int) else float(value)) for key, value in earth.items()},
        "frameRates": {key: float(value) for key, value in frame.items()},
        "deltaTSlopeSecondsPerDay": float(slope),
        "deltaTMagnitudeSeconds": float(delta_t["magnitudeSeconds"]),
        "deltaTJumpSeconds": {key: float(value) for key, value in delta_t["jumpSeconds"].items()},
        "backdateMaxDays": float(backdate),
        "civilCalendarDays": float(calendar_days),
        "civilToTTDays": float(civil_tt_days),
        "civilToTTDegrees": float(civil_tt_degrees),
        "civilToUTDegrees": float(civil_ut_degrees),
        "forwardTTDays": float(forward_tt_days),
        "forwardTTDegrees": float(forward_tt_days * tt_sensitivity),
        "ttInverseDays": float(inverse_days),
        "ttInverseDegrees": float(inverse_days * ut_sensitivity),
        "eraRevolutions": float(era_revolutions),
        "eraDegrees": float(era_deg),
        "contraction": float(k),
        "lightTimeStepDays": float(step_days),
        "lightTimeDays": float(light_time_days),
        "lightTimeAU": float(light_time_au),
        "lightTimeDegrees": float(direction_degrees(light_time_au)),
        "joinDegrees": float(direction_degrees(earth["joinMaxAU"])),
        "sunRateDegPerDay": float(sun_rate),
        "parallaxRateDegPerDay": float(parallax_rate),
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
