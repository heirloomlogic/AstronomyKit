# Geometric Solar Altitude: Numerical Error Budget

What a downstream certificate can rely on when it records a time's scales and Delta T model and computes the Sun's geometric altitude.

## Overview

This article bounds how far `CelestialBody.sun.horizon(at:from:refraction: .none).altitude` can be from the value the same model would give in exact real arithmetic, for a time inside the polynomial coverage of the Earth ephemeris (TT from 1900-01-01 through the end of 2100). Every number comes from one of two places. Derived bounds are computed in exact rational arithmetic from the shipped sources by `Scripts/numerics/solar-altitude/bounds.py` and recorded in `bounds.json`; the derivations are below. Measured values come from `measure.py`, which builds the vendored engine twice from the same source, as shipped in binary64 and rewritten to binary128 with every decimal constant taken exactly, and compares the two over a grid. A measurement is evidence about the sampled inputs on the platform that ran it, not a bound. Where neither exists, the article says so.

It does not bound the distance between the model and the sky. The model is VSOP87B for the Earth, IAU 2006 precession as expressed in the engine, IAU2000B nutation, the Espenak-Meeus or JPL Horizons Delta T polynomials, and a light-time correction with a first-order aberration approximation. `JPLValidationTests` and `AuditValidationTests` compare that model with JPL Horizons at about one arcminute. The numbers here are between ten thousand and a billion times smaller than that.

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

- Per UT day, `utSensitivityDegPerDay` = 362.10°. The Earth Rotation Angle advances `1 + 0.00273781191135448` revolutions per UT day (`era()`), and the altitude changes by at most `cos(latitude) ≤ 1` degrees per degree of hour angle, because `d(altitude)/d(hour angle) = -cos(latitude) sin(azimuth)`. Add the apparent motion of the Sun, at most `speed / radius` = 1.1008° per day of backdated time (the next section), times the Delta T slope factor `1 + 0.0483/86400`, and the rotation of the observer's position, at most `2π × 6388 km / (radius × 1 AU)` = 0.0158° per day for an observer up to 10 km above the ellipsoid.
- Per TT day, `ttSensitivityDegPerDay` = 2.51e-4°. The sum of the derivative bounds of the precession angles (3.85e-5°), the mean obliquity (3.6e-7°), the sidereal-time polynomial (3.5e-5°), the IAU2000B nutation in longitude and obliquity (1.03e-4°), and the equation of the equinoxes (7.4e-5°), each bounded by `Σ k |c_k| T^(k-1)` with `T = 1.01` centuries, and for the series by `Σ (|A| + |A'| T) |n · ω| + |A'|` over the 77 terms with the fundamental argument rates in the engine.

## Time conversion

Civil UTC to TT (`CivilTime.terrestrialTime`, Swift) is `utc + (offset + rate × (utc - start)) / 86400`: five binary64 operations. With unit roundoff `u = 2^-53`, the standard model of floating-point arithmetic (Higham, *Accuracy and Stability of Numerical Algorithms*, 2nd ed., §2.2) bounds the error by `2u |tt| + 3u (|offset| + |rate| × span) / 86400`. For `|tt| ≤ 36889.5` days, an offset up to 69.184 s and the pre-1972 rates below 0.0013 s/day over segments shorter than 700 days, that is `civilToTTDays` = 8.19e-12 day (0.71 µs). Through the TT sensitivity it moves the altitude by `civilToTTDegrees` = 2.05e-15°. Derived.

TT to UT (`Astronomy_TerrestrialTimeWithDeltaT`) iterates until `|tt - (ut + ΔT(ut)/86400)| ≤ max(1e-12, 2u |tt|)` and then stores the requested `tt` exactly. The tolerance is `ttInverseDays` = 8.19e-12 day at the coverage edge, so the stored `ut` is within that of the model's UT, plus the rounding of the Delta T polynomial itself, measured below 6.0e-13 s (6.9e-18 day) over the grid. Through the UT sensitivity the tolerance alone is worth `ttInverseDegrees` = 2.97e-9°. Derived. This is the largest term in the budget, and it applies only when the engine derived `ut` from `tt`; a `ut` supplied through `AstroTime(ut:deltaTModel:)` or `AstroTime(tt:ut:deltaTModel:)` carries no inverse error.

## Earth rotation angle

`era()` forms `thet1 = 0.7790572732640 + 0.00273781191135448 × ut` in revolutions, adds `fmod(ut, 1)`, reduces by `fmod` (exact), and multiplies by 360. The three roundings happen at up to `|thet1| + 1` revolutions, 102.8 at the coverage edge, so the angle is within `4u × 102.8 × 360` = `eraDegrees` = 1.64e-11°. Derived. This is the largest rounding term inside the coverage, and it grows linearly with `|ut|`.

## Earth position

Inside the coverage the Earth comes from degree-12 Chebyshev polynomials on eight-day segments (`PolynomialPosition`, Clenshaw recurrence). Three bounds follow exactly from the 9,177 shipped segments:

- Speed `speedAUPerDay` ≤ 0.018708 AU/day. Each velocity component is bounded by `Σ k² |a_k| / (width/2)`, since `|T_k'(x)| ≤ k²` on `[-1, 1]`.
- Radius `radiusAU` ≥ 0.97384 AU. The exact radius on a one-day grid is at least 0.98319 AU, widened by half a day at the speed bound.
- Join discontinuity `joinMaxAU` ≤ 2.07e-13 AU per boundary, as the largest difference between the end value of one segment and the start value of the next (`Σ a_k` and `Σ (-1)^k a_k`), summed over all boundaries 2.55e-10 AU (`joinSumAU`). Seen from the Earth, one jump moves the Sun's direction by at most `2.07e-13 / 0.97384` rad = 1.22e-11°. The shipped function is discontinuous there; an enclosure of a time interval that crosses a boundary must widen by this much.

The rounding of the polynomial evaluation is measured, not derived: the largest difference between the binary64 and binary128 Earth position over the coverage grid was 3.22e-16 AU per axis, which is at most 3.3e-14° of direction. The fit error between the polynomials and the compensated full series was measured during qualification at 53 samples per segment, at most 0.41 of the `max(1e-12, |reference| × 1e-12)` AU budget (see `Scripts/performance/polynomial/README.md`); there is no bound between samples, and the shipped model is the polynomial, not the series.

## Light-time termination

`Astronomy_CorrectLightTravel` iterates `τ ← |E(t - τ)| / c` and returns the position evaluated at the last `τ_n` once `|τ_{n+1} - τ_n| < 1e-9` day. The map is a contraction with constant `k ≤ speed / c` = 1.08e-4, so `|τ_n - τ*| ≤ |τ_{n+1} - τ_n| / (1 - k)` for the exact fixed point `τ*`. The stop test compares TT values rounded at `ulp(|tt|)`, so the exact step can exceed `1e-9` by `4u |tt|` = 1.6e-11 day. Together `lightTimeDays` = 1.0165e-9 day, and the returned position is within `speed × 1.0165e-9 × (1 + 0.0483/86400)` = 1.90e-11 AU of the position at `τ*`, which is `lightTimeDegrees` = 1.12e-9° of direction. Derived. The loop gives up after ten iterations with `AstronomyError.noConvergence`; from the contraction constant, three or four iterations always suffice inside the coverage, so that error is not reachable there.

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

For a time inside the coverage with a finite `ut` and `tt`, an observer within `±90°` latitude and up to 10 km above the ellipsoid, and `refraction: .none`:

| Term | Degrees | Status |
|---|---|---|
| TT to UT inverse tolerance, if the engine derived `ut` (`init(_:)`, `init(year:...)`, `init(tt:)`) | 2.97e-9 | Derived |
| Light-time termination | 1.12e-9 | Derived |
| Earth Rotation Angle rounding | 1.64e-11 | Derived |
| Join discontinuity, per boundary crossed | 1.22e-11 | Derived |
| Civil UTC to TT rounding, if the time came from a civil date | 2.1e-15 | Derived |
| Polynomial evaluation, frames, sidereal time, horizon transform, libm | in the 1e-11° decade or below on all but the 27 light-time flips observed on 1,168,398 samples; no bound | Measured |

A certificate can add the derived terms that apply to how its time was constructed, and treat the measured line as evidence about this platform and grid rather than as a bound. The largest difference actually observed between the shipped arithmetic and the binary128 reference, 1.006e-9°, is below the sum of the derived terms that apply to that input; the light-time term alone covers it.

## Supported dates and unsupported cases

- The polynomial bounds (speed, radius, joins) and the measured Earth rounding hold for TT in `[-36524.5, 36889.5)` days, 1900-01-01 through the end of 2100. Outside, the full series is summed with compensated addition: the measured values above apply to the sampled century on either side, and nothing in this article is derived for it. The accepted range of the ephemeris is ±1,461,000 days (``AstroTime``); beyond it every position throws `badTime`.
- Refraction is excluded. `.normal` and `.jplHorizons` apply an empirical model whose error is not numerical.
- Only the Sun. The Moon, planets, and stars follow different paths with their own series and caches.
- The named Delta T models only. A function installed through the C API carries no slope bound; its time's ``AstroTime/deltaTModel`` is `nil`.
- An invalid time (NaN scales) or an observer outside the validated range throws before any arithmetic runs: `badTime` and `invalidParameter`.
- A `ut` far outside the coverage grows the Earth Rotation Angle term linearly: `4u (0.779 + 0.0027378 |ut| + 1) × 360°`.
- Nothing here covers other platforms' libm, other toolchains, or `-ffast-math` builds, which this package does not use.

## Reproducing

```sh
python3 Scripts/numerics/solar-altitude/bounds.py            # derived bounds, exact arithmetic
python3 Scripts/numerics/solar-altitude/measure.py --step 0.377   # the coverage grid above (needs libquadmath)
python3 Scripts/numerics/solar-altitude/measure.py --outside --step 7.3
python3 Scripts/numerics/solar-altitude/measure.py --step 0.377 --optimization=-O0
```
