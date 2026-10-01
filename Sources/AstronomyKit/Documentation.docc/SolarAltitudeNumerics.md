# Geometric Solar Altitude: Numerical Error Budget

What a downstream certificate can rely on when it records a time's scales and Delta T model and computes the Sun's geometric altitude.

## Overview

This article bounds how far `CelestialBody.sun.horizon(at:from:refraction: .none).altitude` can be from the value the same model would give in exact real arithmetic, for a time inside the polynomial coverage of the Earth ephemeris (TT from 1900-01-01 through the end of 2100). Every number comes from one of two places. Derived bounds are computed in exact rational arithmetic from the shipped sources by `Scripts/numerics/solar-altitude/bounds.py` and recorded in `bounds.json`; the derivations are below, and `test_bounds.py` checks that every figure quoted here is current and rounded away from the exact value, never toward it. Measured values come from `measure.py`, which builds the vendored engine twice from the same source, as shipped in binary64 and rewritten to binary128 with every decimal constant taken exactly, and compares the two over a grid. A measurement is evidence about the sampled inputs on the platform that ran it, not a bound. Where neither exists, the article says so.

It does not bound the distance between the model and the sky. The model is VSOP87B for the Earth, IAU 2006 precession as expressed in the engine, IAU2000B nutation, the Espenak-Meeus or JPL Horizons Delta T polynomials, and a light-time correction with a first-order aberration approximation. `JPLValidationTests` and `AuditValidationTests` compare that model with JPL Horizons at about one arcminute. The numbers here are between ten thousand and a billion times smaller than that.

Rounding is bounded with the standard model of floating-point arithmetic (Higham, *Accuracy and Stability of Numerical Algorithms*, 2nd ed., §2.2): each binary64 operation returns its exact result times `1 + δ` with `|δ| ≤ u = 2^-53`, and so does the conversion of a decimal literal.

## What the calculation reads

Start from an ``AstroTime`` with scales `tt` and `ut` and a captured ``AstroTime/deltaTModel`` (see "Delta T Model" under ``AstroTime``), and an ``Observer``. The path to the altitude is `Astronomy_Equator(BODY_SUN, EQUATOR_OF_DATE, ABERRATION)` followed by `Astronomy_Horizon(REFRACTION_NONE)` in the vendored engine. Each stage reads a different input.

| Stage | Reads | Notes |
|---|---|---|
| Earth heliocentric position | `ut` and the Delta T model | The light-time loop backdates through `Astronomy_AddDays`, which derives TT from `ut - τ` with the time's Delta T function. The position does not read the input `tt`, except that `tt` must be inside the accepted range and seeds the first iteration. |
| Precession, nutation, obliquity | `tt` | Polynomials in centuries from J2000 and the IAU2000B series. |
| Sidereal time | `ut` for the Earth Rotation Angle, `tt` for precession in right ascension and the equation of the equinoxes | |
| Observer vector and horizon frame | Sidereal time, latitude, longitude, height | |

So a pair whose `tt` is not the model's TT for its `ut` is accepted and evaluated as given: the Sun is placed from `ut`, the frames from `tt`. `AstroTime(tt:ut:deltaTModel:)` documents this.

## Sensitivities

Two numbers convert an error in a time scale into an error in altitude. Both are derived.

- Per UT day, `utSensitivityDegPerDay` = 362.11°. The Earth Rotation Angle advances `1 + 0.00273781191135448` revolutions per UT day (`era()`), and the altitude changes by at most `cos(latitude) ≤ 1` degrees per degree of hour angle, because `d(altitude)/d(hour angle) = -cos(latitude) sin(azimuth)`. Add the apparent motion of the Sun, `sunRateDegPerDay` = 1.1008° per day of backdated time (`speed / radius` from the next section, raised by the light-time fixed point's own drift, a factor `1 + k / (1 - k)` with the contraction constant `k` below), times the Delta T slope factor `1 + deltaTSlopeSecondsPerDay / 86400`, and the rotation of the observer's position with the same angular rate, `parallaxRateDegPerDay` = 0.0159° per day for an observer up to 10 km above the ellipsoid (`EARTH_EQUATORIAL_RADIUS_KM + 10 km` over the radius bound).
- Per TT day, `ttSensitivityDegPerDay` = 2.51e-4°. The sum of the derivative bounds of the precession angles (`precessionDegPerDay` = 3.85e-5°), the mean obliquity (`obliquityDegPerDay` = 3.57e-7°), the sidereal-time polynomial (`siderealPolynomialDegPerDay` = 3.51e-5°), the IAU2000B nutation in longitude and obliquity (`nutationDegPerDay` = 1.04e-4°), and the equation of the equinoxes (`equinoxesDegPerDay` = 7.37e-5°), each bounded by `Σ k |c_k| T^(k-1)` with `T = 1.01` centuries, and for the series by `Σ (|A| + |A'| T) |n · ω| + |A'|` over the 77 terms with the fundamental argument rates in the engine.

The Delta T slope, `deltaTSlopeSecondsPerDay` = 0.00647 s per UT day, is the largest `|dΔT/d ut|` over the pieces of `Astronomy_DeltaT_EspenakMeeus` the coverage reaches. The engine's year is `2000 + (ut - 14) / 365.24217`, so the coverage starts at 1899.96, inside the piece for 1860 through 1900, and ends in the piece for 2050 through 2150; each piece's derivative is bounded by Taylor expansion about the midpoints of one-year subintervals. Delta T itself stays within `deltaTMagnitudeSeconds` = 206 s there. `Astronomy_DeltaT_JplHorizons` evaluates the same pieces with `ut` held at the year 2017 from then on, so both named models are covered.

## Time conversion

Each initializer rounds differently, and a certificate adds the terms for the one that built its time. An error in one scale reaches the other through the model: `init(tt:)` derives `ut` from the stored `tt`, and the forward path derives `tt` from the stored `ut`, so each term below carries its error through both sensitivities where the other scale follows from it. `init(tt:)` stores `tt` exactly, `init(ut:)` stores `ut` exactly, and `init(tt:ut:)` stores both, so those paths carry one scale only.

Calendar arithmetic. `init(_:)` turns a `Date` into days in three operations: Foundation's `timeIntervalSince1970` adds the reference-date offset to the interval a `Date` stores, rounding at the magnitude of the seconds since 1970, then `(seconds - offset) / 86400`. `init(year:...)` goes through `Astronomy_MakeTime`, which adds `hour / 24`, `minute / 1440`, and `second / 86400` to the day number: three sums rounding at up to `u (|utc| + 1)` each, with the three quotients together within `u` for components in their documented ranges. Either way the civil day count is within `civilCalendarDays` = 1.36e-11 day of the exact value, for a civil time within a day of the coverage. Derived.

Civil UTC to TT, from 1961 on (`CivilTime.terrestrialTime`, Swift) is `utc + (offset + rate × (utc - start)) / 86400`: five operations plus the rounding of the `offset` and `rate` literals, bounded for the segment of the bundled table where `offset + rate × span` is largest, with the calendar error arriving through the conversion's slope `1 + rate / 86400`. Together `civilToTTDays` = 1.76e-11 day (1.53 µs). The stored `tt` is off by that, and `init(tt:)` then derives `ut` from the stored `tt`, so the model's UT for it is off from the exact civil instant's UT by the same amount times `1 / (1 - slope / 86400)`, on top of the inverse term below. Through both sensitivities, `civilToTTDegrees` = 6.38e-9°. Derived. A civil time within the calendar rounding of a segment start, including the table's first, can land on either side of it; the stored `tt` then differs from the exact conversion by that segment's step, not by this bound.

Civil dates before 1961-01-01, where the table starts, are taken as UT1: the calendar rounding lands on `ut` instead, and TT follows forward from that `ut`, so the stored `tt` is off by the same amount times `1 + slope / 86400` on top of the forward rounding below. Through both sensitivities, `civilToUTDegrees` = 4.89e-9°. Derived.

UT to TT (`TimeFromDaysWithDeltaT`: `init(ut:)`, the civil path before 1961, and every backdated time) is `fl(ut + fl(ΔT(ut) / 86400))`: two roundings, `forwardTTDays` = 4.10e-12 day at the coverage edge, plus the rounding of the Delta T polynomial itself, measured below 6.0e-13 s (6.9e-18 day) over the grid. Through the TT sensitivity, `forwardTTDegrees` = 1.03e-15°. Derived.

TT to UT (`Astronomy_TerrestrialTimeWithDeltaT`: `init(tt:)` and the civil path from 1961 on) iterates until `|tt - time.tt| ≤ max(1e-12, 2 × DBL_EPSILON × |tt|)`, that is `4u |tt|` inside the coverage, and then stores the requested `tt` exactly. `time.tt` is the forward value above and the comparison rounds once more, so the stored `ut` satisfies `|tt - (ut + ΔT(ut) / 86400)| ≤ 4u |tt| / (1 - u) + forwardTTDays`, and the model's own UT for `tt` is within that times `1 / (1 - slope / 86400)` of it: `ttInverseDays` = 2.05e-11 day, plus the measured Delta T rounding. Through the UT sensitivity the derived part is `ttInverseDegrees` = 7.42e-9°. Derived. This is the largest term in the budget. A `ut` supplied through `init(ut:)` or `init(tt:ut:)` carries no inverse error.

The model has no UT for some TT values and two for others. The Delta T pieces do not meet: where Delta T steps up at a piece boundary, the TT values between the two sides of the step have no UT; where it steps down, a TT in the overlap has two. The steps the coverage reaches, computed exactly from the pieces (JPL Horizons shares those up to 2017):

| Year | Step in Delta T (s) | Inverse behavior |
|---|---|---|
| 1900 | -0.0885 (`y1900`) | Two UTs; the loop returns the first reached from `ut = tt` |
| 1920 | 0.0124 (`y1920`) | Gap |
| 1941 | 0.000882 (`y1941`) | Gap |
| 1961 | 0.0297 (`y1961`) | Gap |
| 1986 | 0.00989 (`y1986`) | Gap |
| 2005 | -0.0501 (`y2005`) | Two UTs |
| 2050 | -0.00100 (`y2050`) | Two UTs; Espenak-Meeus only |

At a step down the stored `ut` is one of the two solutions, within `ttInverseDays` of it; the two differ by at most the step over 86400, times `1 / (1 - slope / 86400)`, and the recorded `ut` identifies which one. For a TT inside a gap the fixed-point loop cannot converge; after 128 iterations the inverse bisects to the first binary64 `ut` at which the engine's Delta T evaluation lands on the later piece and stores the requested `tt`. That pair is not a model pair and nothing here bounds it: a certificate must refuse a TT inside a gap, or record the pair and treat it as supplied. The gaps sit where the engine's year reaches 1920, 1941, 1961, and 1986 and are as wide as the steps.

## Earth rotation angle

`era()` forms `thet1 = 0.7790572732640 + 0.00273781191135448 × ut` in revolutions, adds `fmod(ut, 1)`, reduces by `fmod` (exact), multiplies by 360, and adds 360 to a negative result. Seven roundings: each literal to binary64, the product, the two sums at up to `eraRevolutions` = 102.8 revolutions at the coverage edge, the scaling, and the fix-up, the last two below 360°. Together `eraDegrees` = 1.64e-11°. Derived. This is the largest rounding term inside the coverage, and it grows linearly with `|ut|`.

## Earth position

Inside the coverage the Earth comes from degree-12 Chebyshev polynomials on eight-day segments (`PolynomialPosition`, Clenshaw recurrence). Three bounds follow exactly from the shipped segments (`segments` = 9,177):

- Speed `speedAUPerDay` ≤ 0.018708 AU/day. Each velocity component is bounded by `Σ k² |a_k| / (width/2)`, since `|T_k'(x)| ≤ k²` on `[-1, 1]`.
- Radius `radiusAU` ≥ 0.97383 AU and `radiusMaxAU` ≤ 1.0262 AU. On a one-day grid that includes both ends of every segment the exact radius is at least `radiusGridAU` = 0.98319 AU; every instant is within half a day of a grid point of its own segment, so the grid bounds widen by half a day at the speed bound.
- Join discontinuity `joinMaxAU` ≤ 2.20e-13 AU per boundary, the length of the vector difference between the end value of one segment and the start value of the next (`Σ a_k` and `Σ (-1)^k a_k` per axis), summed over all boundaries 2.85e-10 AU (`joinSumAU`), which agrees with the issue's `< 1e-9` figure. Seen from the Earth, one jump turns the Sun's direction by at most `asin(joinMaxAU / radiusAU)` = `joinDegrees` = 1.29e-11°. The shipped function is discontinuous there; an enclosure of a time interval that crosses a boundary must widen by this much.

The rounding of the polynomial evaluation is measured, not derived: the largest difference between the binary64 and binary128 Earth position over the coverage grid was 3.22e-16 AU per axis, which is at most 3.3e-14° of direction. The fit error between the polynomials and the compensated full series was measured during qualification at 53 samples per segment, at most 0.41 of the `max(1e-12, |reference| × 1e-12)` AU budget (see `Scripts/performance/polynomial/README.md`); there is no bound between samples, and the shipped model is the polynomial, not the series.

## Light-time termination

`Astronomy_CorrectLightTravel` iterates `τ ← |E(t - τ)| / c`, backdating through `Astronomy_AddDays` (`ut - τ`, then the forward TT above), and returns the position evaluated at the last `τ_n` once the two backdated TT values differ by less than 1e-9 day. The map is a contraction with constant `contraction` = 1.09e-4 (`speed × (1 + slope / 86400) / c`), so `|τ_n - τ*| ≤ (|τ_{n+1} - τ_n| + ε) / (1 - k)` for the exact fixed point `τ*`, where `ε` is the rounding each iterate carries: the vector length (three squares, two sums, and a square root), the two operations forming `ut - τ`, and the shift of the distance by `speed × forwardTTDays`. The stop test compares forward-rounded TT values, so the step in UT can reach `lightTimeStepDays` = 1.009e-9 day; together `lightTimeDays` = 1.013e-9 day. The returned position, evaluated at the forward-rounded TT of `τ_n`, is within `lightTimeAU` = 1.91e-11 AU of the position at `τ*`, which is `lightTimeDegrees` = 1.12e-9° of direction. Derived. The rounding of the Earth position inside the distance (measured above) is not in this term. The loop gives up after ten iterations with `AstronomyError.noConvergence`; from the contraction constant, three or four iterations always suffice inside the coverage, so that error is not reachable there. The backdated time is never more than `backdateMaxDays` = 0.00593 day (8.6 minutes, `radiusMaxAU / c`) before the input.

The measurement shows this term directly. The step `|τ_{n+1} - τ_n|` is about `(radial speed / c) × τ`, which crosses the 1e-9-day threshold twice a year. Near those epochs the binary64 and binary128 builds stop one iteration apart (a flip, below), and their results differ by the full termination bound: the largest altitude differences on every grid (1.006e-9° inside the coverage, 1.025e-9° outside) sit at those epochs, with the whole difference in the geocentric vector and none in the heliocentric Earth position at the input time. Away from them the difference is in the 1e-11° decade and below.

## Frame rotation and the horizon transform

Precession and nutation matrices, the observer vector, the sidereal time, and `Astronomy_Horizon` are products, sums, and libm calls with no useful closed-form bound in this article. They are measured. Over the coverage grid (194,733 epochs at 0.377-day spacing, six observers from the equator to 89.9° latitude and from sea level to 1000 m, 1,168,398 samples; `measure.py --step 0.377`, Apple clang `-O2` and Apple libm, arm64; the same grid against a `-O0` build gave the same 1.006e-9°):

| Quantity | Largest difference, binary64 against binary128 |
|---|---|
| Altitude | 1.006e-9° |
| Azimuth | 3.48e-9° (ill-conditioned near the zenith) |
| Right ascension and declination of date | 7.39e-11 h, 1.29e-10° |
| Right ascension and declination, J2000 | 7.39e-11 h, 1.31e-10° |
| Geocentric Sun vector (J2000) | 1.74e-11 AU per axis |
| Heliocentric Earth position at the input time | 3.22e-16 AU per axis |
| Apparent sidereal time | 3.56e-13 h |
| Delta T (Espenak-Meeus) | 5.98e-13 s |

Altitude differences by decade over those samples: 1e-20: 1, 1e-19: 5, 1e-18: 58, 1e-17: 484, 1e-16: 5,044, 1e-15: 49,251, 1e-14: 254,266, 1e-13: 618,401, 1e-12: 240,838, 1e-11: 23, 1e-10: 25, 1e-9: 2 (each count is the number of samples whose altitude difference lies in that decade).

Outside the coverage, where the full VSOP87B series is summed (the century on either side, 10,008 epochs, 60,048 samples), the Earth position differs by up to 2.83e-13 AU per axis, the altitude by up to 1.025e-9° (the light-time flips again; 17 samples at 1e-10° or more), and the rest stays at or below the 1e-11° decade.

The binary64 build is not bit-identical across optimization levels: the equator and horizon stages differ by up to 2.8e-14° of altitude between `-O0` and `-O2` with Apple clang, consistent with constant folding of `sin` and `cos` of constant angles at compile time. MAINTAINING.md already makes no bit-identity promise across toolchains or optimization levels.

## libm

The path calls `sin`, `cos`, `atan2`, `hypot`, `sqrt`, and `fmod`. `sqrt` is correctly rounded and `fmod` is exact under IEEE 754 and C. For the others, this investigation found no proven bound for any platform this package builds on. Two documented sources describe them:

- The GNU C Library manual (§19.7, "Known Maximum Errors in Math Functions") states a goal, not a bound: each function behaves "as if it computes an infinite-precision result that is within a few ulp" of the mathematical value, and "the math testsuite only flags results larger than 9ulp" as errors.
- Gladman, Innocente, Mather, Ozaki, and Zimmermann, *Accuracy of Mathematical Functions in Single, Double, Double Extended, and Quadruple Precision* (August 2026 version; the glibc manual cites it), report the largest known double-precision errors found by a black-box search, which the authors state are lower bounds on the largest error. For GNU libc 2.44: `sin` 0.516, `cos` 0.516, `atan2` 0.524, `hypot` 0.792, `sqrt` 0.500 ulp. For the Apple Math Library 26.5.2 (Darwin 25.5.0): `sin` 0.944, `cos` 0.948, `atan2` 0.747, `hypot` 1.21, `sqrt` 0.500 ulp. Apple publishes no accuracy specification for its libm.

The measurement above includes whatever libm the binary64 build linked, so it is evidence about that library on that machine. The CI check (`measure.py --check`, Linux, glibc) repeats a reduced grid on every pull request and fails above the ceilings in `bounds.json`.

## The budget

For a time inside the coverage with a finite `ut` and `tt`, a TT outside the Delta T gaps, an observer within `±90°` latitude and up to 10 km above the ellipsoid, and `refraction: .none`:

| Term | Degrees | Status |
|---|---|---|
| TT to UT inverse, if the engine derived `ut` (`init(tt:)`, `init(_:)` and `init(year:...)` from 1961 on) | `ttInverseDegrees` = 7.42e-9 | Derived |
| Calendar and civil UTC to TT rounding, carried into the derived `ut` (`init(_:)` and `init(year:...)` from 1961 on) | `civilToTTDegrees` = 6.38e-9 | Derived |
| Calendar rounding taken as UT, carried into the forward `tt` (`init(_:)` and `init(year:...)` before 1961) | `civilToUTDegrees` = 4.89e-9 | Derived |
| Light-time termination | `lightTimeDegrees` = 1.12e-9 | Derived |
| Earth Rotation Angle rounding | `eraDegrees` = 1.64e-11 | Derived |
| Join discontinuity, per boundary crossed | `joinDegrees` = 1.29e-11 | Derived |
| UT to TT rounding, if the engine derived `tt` (`init(ut:)`, civil before 1961) | `forwardTTDegrees` = 1.03e-15 | Derived |
| Polynomial evaluation, frames, sidereal time, horizon transform, libm, Delta T polynomial | in the 1e-11° decade or below on all but the 27 light-time flips observed on 1,168,398 samples; no bound | Measured |

A certificate can add the derived terms that apply to how its time was constructed, and treat the measured line as evidence about this platform and grid rather than as a bound. The largest difference actually observed between the shipped arithmetic and the binary128 reference, 1.006e-9°, is below the sum of the derived terms that apply to that input; the light-time term alone covers it.

## Supported dates and unsupported cases

- The polynomial bounds (speed, radius, joins) and the measured Earth rounding hold where the Earth position is evaluated: at the backdated TT, up to `backdateMaxDays` before the input, which must lie in `[-36524.5, 36889.5)` days, 1900-01-01 through the end of 2100. For an input in the first `backdateMaxDays` of the coverage, or a supplied pair whose `ut` puts the backdated TT before it, the full series is summed with compensated addition instead: the measured values above apply to the sampled century on either side, and nothing in this article is derived for it. The accepted range of the ephemeris is ±1,461,000 days (``AstroTime``); beyond it every position throws `badTime`.
- A TT inside one of the four Delta T gaps (1920, 1941, 1961, 1986) is excluded; the inverse stores a pair the model does not relate, as described under "Time conversion".
- Refraction is excluded. `.normal` and `.jplHorizons` apply an empirical model whose error is not numerical.
- Only the Sun. The Moon, planets, and stars follow different paths with their own series and caches.
- The named Delta T models only. A function installed through the C API carries no slope, magnitude, or step bound; its time's ``AstroTime/deltaTModel`` is `nil`.
- An invalid time (NaN scales) or an observer outside the validated range throws before any arithmetic runs: `badTime` and `invalidParameter`.
- A `ut` far outside the coverage grows the Earth Rotation Angle term linearly with `0.779 + 0.0027378 |ut| + 1` revolutions.
- Nothing here covers other platforms' libm, other toolchains, or `-ffast-math` builds, which this package does not use.

## From Swift

`Sun.altitudeObservation(at:from:deltaTModel:)` takes a civil `Date`, `altitudeObservation(terrestrialTime:from:deltaTModel:)` a TT, and `altitudeObservation(universalTime:from:deltaTModel:)` a UT; the Delta T model is a required argument. Each builds the ``AstroTime`` with the matching initializer, evaluates `horizon(refraction: .none)`, and returns a ``SolarAltitudeObservation``: the time with both scales and its model, the observer, the altitude, and an ``SolarAltitudeObservation/ErrorBound`` that sums the derived terms for that construction. A `Date` from 1961 on adds `civilToTTDegrees` and `ttInverseDegrees`; a `Date` before 1961 adds `civilToUTDegrees` and `forwardTTDegrees`; a TT adds `ttInverseDegrees`; a UT adds `forwardTTDegrees`; every observation adds `lightTimeDegrees` and `eraDegrees`. The total rounds each addition up, so it is never below the exact sum. The measured line is not in the bound, and the type's documentation says so.

The constants live in `Sources/AstronomyKit/SolarAltitudeBounds.swift`, which `bounds.py --write` generates from the same exact values as `bounds.json`, each rounded to binary64 away from zero, and `bounds.py --check` verifies. No number in the Swift API is typed by hand.

The entry points throw ``SolarAltitudeObservation/Unsupported`` for the cases listed above: a TT outside the coverage, including the first `backdateMaxDays` of it, where the loop backdates into the series; a TT inside a Delta T gap, detected because the stored pair's residual `|tt - fl(ut + fl(ΔT(ut) / 86400))|` exceeds the inverse tolerance, which a converged inverse never does and a bisected one always does; a civil date within `civilCalendarDays` of a UTC segment start; an observer more than 10 km from the ellipsoid. A non-finite time throws `badTime` and an invalid observer `invalidParameter`, as `horizon` does. No entry point takes an ``AstroTime``: a time does not record which initializer built it, and the terms depend on that. A time the engine derived, such as a search result, is rebuilt exactly from its `universalTime` and `deltaTModel`. For an enclosure over an interval, ``SolarAltitudeObservation/joinDiscontinuityDegrees`` is the step per polynomial boundary and ``SolarAltitudeObservation/polynomialSegmentDays`` the boundary spacing from the start of ``SolarAltitudeObservation/polynomialCoverage``.

## Reproducing

```sh
python3 Scripts/numerics/solar-altitude/bounds.py            # derived bounds, exact arithmetic
python3 Scripts/numerics/solar-altitude/measure.py --step 0.377   # the coverage grid above (needs libquadmath)
python3 Scripts/numerics/solar-altitude/measure.py --outside --step 7.3
python3 Scripts/numerics/solar-altitude/measure.py --step 0.377 --optimization=-O0
```
