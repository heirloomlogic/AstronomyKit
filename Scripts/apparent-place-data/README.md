# Apparent-place numerical foundations

This archive qualifies the internal building blocks for issue #256. The public position, state, topocentric and eclipse routes still use their existing models in this first link. Public integration, independent Horizons comparisons and the replacement solar-altitude proof belong to the second link.

## Source and reproduction

`manifest.json` pins eight unmodified ERFA v2.0.1 files at commit `9915ba38c9365f8b0738269b8c2ac1fdd5f8dee3`, with original notices and SHA-256 hashes. `EngineApparentPlace.swift` derives its aberration and finite-source deflection formulas from `ab.c` and `ld.c`; analytic rates and validation are AstronomyKit additions. The literal published cases in `t_erfa_c.c` retain their 1e-12 tolerances. `dtdb.c` supplies an independently parsed decimal time model for the light-time fixtures.

Run `.build/numerics-venv/bin/python Scripts/generate-apparent-place-fixtures.py --check` after installing `Scripts/solar-numerics/requirements.txt`. The generator verifies every archive hash, compiles the original C into a temporary library, and checks nine direction/rate cases plus six light-time roots. Direction values come from compiled ERFA; directional derivatives come from independent 80-digit Python formulas. Light-time roots use 80-digit Newton solving with the original decimal Fairhead coefficients, checked against compiled `eraDtdb`. The generated Swift fixture is structural-checked and numerically replayed; Swift tests use 2e-15 direction and 2e-16 directional-rate tolerances on those samples.

## Time and derivatives

[JPL Horizons](https://ssd.jpl.nasa.gov/horizons/manual.html) uses TDB for its barycentric vector ephemerides and distinguishes geometric, light-time and stellar-aberration corrections. [ERFA `eraDtdb`](https://github.com/liberfa/erfa/blob/9915ba38c9365f8b0738269b8c2ac1fdd5f8dee3/src/dtdb.c) gives the adopted periodic relation between TT and TDB. The source trajectory is parameterized by TT; propagation uses elapsed TDB. Writing `T(t) = t + (TDB−TT)(t)/86400`, the solver finds `T(t) − T(te) = |target(te) − observer(t)|/c`. With `n` the observer-to-target unit vector, implicit differentiation gives `dte/dt = (T′(t) + n·vo/c)/(T′(te) + n·vt/c)`. Target and observer velocities in this expression are per TT day.

The delay is computed from time differences and offset differences, avoiding subtraction of full Julian dates. Iteration stops when the emitted TT repeats or the delay changes by at most four ULP; twenty unsuccessful iterations throw. Zero separation, invalid components, superluminal inputs and a TDB delay over one day are refused. The target callback owns source-domain checks at every emission epoch. The solver does not include Shapiro delay and does not prove convergence for arbitrary discontinuous callbacks.

The six independent root fixtures span the accepted TT interval. At −1000, 0 and 100 TT days, their precision distinguishes the TDB equation from a TT-only equation. Near the distant endpoints, the conversion can be smaller than one representable TT step; those rows test endpoint arithmetic without claiming that distinction. Reception-TT state derivatives include both clock rates. Aberration uses coordinate velocity per TDB day divided by c; `observerBeta` converts TT velocity and acceleration with both the TDB rate and its derivative.

## Selected trajectories and domains

Earth kinematics retain the existing heliocentric position and velocity bits. Their acceleration analytically differentiates the selected Chebyshev fit or complete VSOP87B series. Polynomial seams use the selected right-hand branch; fitted trajectories are not assumed to have continuous acceleration. Synthetic polynomial and harmonic tests check the second-derivative recurrences independently, while actual trajectory tests compare analytic acceleration with five-point velocity differences away from seams.

The solar kinematics use the compiled DE441 cubic table already qualified in `Scripts/pluto-data/de441-evidence.json`, with the existing ICRF-to-EQJ bias. Its TDB coverage is `[−1461016.5, 1461015.5)` days. The accepted TT endpoints lie more than fifteen days inside that source coverage; no new kernel or interpolation coefficients are introduced. The interpolation is C1, so its acceleration is the selected record derivative and may jump at a boundary. TT acceleration includes both the squared TDB rate and the TDB second derivative. Earth barycentric kinematics compose this solar origin with the selected Earth heliocentric trajectory; existing public barycentric functions are unchanged.

The new kinematic entry points accept only `|TT| ≤ 1461000`; endpoint-adjacent tests reject strict exterior values. A later body-level light-time provider must qualify its own retarded domain before using the solver at a public endpoint. This link does not claim that every existing body source already supplies that padding.

## Limits

`eraAb` includes relativistic normalization and the solar gravitational-potential term. `eraLd` supports a finite source and preserves its unnormalized output convention. A positive deflection limiter clamps the denominator; at equality the rate follows the limiter branch, where a two-sided derivative need not exist. Unit-direction input validation allows squared-length error up to 1e-6 to admit ERFA’s rounded published example; it does not normalize those inputs silently.

The tests establish agreement for the pinned formulas, sampled rates, selected trajectories and tested error paths. They do not bound all floating-point error, ephemeris error or physical apparent-place accuracy. No solar-limb limiter, deflector-epoch prescription, eclipse convention or public Aberration behavior is selected by this foundation alone.
