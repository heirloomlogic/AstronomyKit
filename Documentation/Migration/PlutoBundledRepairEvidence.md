# Pluto body-center coefficient repair

The bundled Pluto candidate uses geometric ICRF position and analytic velocity for body center 999 relative to the Sun: DE440 SSB→9 minus DE440 SSB→10 plus PLU060 9→999. It preserves the approved domain `1900-01-01 TT <= epoch < 2131-01-01 TT`; barycenter 9 is never substituted for body center 999. This document records source/data evidence. The common C evaluator, production integration, public API event assessment, package cost, and CI results are recorded by the integrating workstream.

The source and 128 fresh epochs were frozen in [pluto-plan.json](../../Scripts/ephemeris/pluto-plan.json) before accuracy residual evaluation. Its representation was finalized for immutable compiled C arrays before fresh Horizons acquisition. The archived `geometric-event-assessment.json`, its 18 old Pluto failures/successes, and all previous reports and allowances remain unchanged. New candidate results are [pluto-evidence.json](../../Scripts/ephemeris/pluto-evidence.json).

## Official sources and attribution

The [NAIF PLU060 comments](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/plu060.cmt) identify the Pluto satellite solution, its DE440 planetary basis, and coverage from January 1800 into December 2199. Local SPK inspection confirms two frame-1/type-2 target-999/center-9 segments meeting at JD 2456293.5 TDB. Both segments are necessary: convenience lookup by `(9,999)` returns only one and would lose part of the approved interval. The generator sorts and checks contiguous source segments explicitly. DE440s supplies separate SSB→9 and SSB→10 segments; it does not supply 9→999.

| Original source | Bytes | SHA-256 |
| --- | ---: | --- |
| [de440s.bsp](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp) | 32,726,016 | `c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2` |
| [plu060.bsp](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/plu060.bsp) | 135,207,936 | `dfbb102491a26ed41ae08ca3f8963f22f0219df1d8f265ab87b9ad825a826fc6` |

NASA/JPL Solar System Dynamics produced the original ephemerides, distributed through NASA/JPL NAIF. The renamed derivative coefficient products identify **Heirloom Logic / AstronomyKit** as their producer; they are not represented as original JPL kernels. [NAIF rules](https://naif.jpl.nasa.gov/naif/rules.html) permit kernel use and describe redistribution, modified-product attribution, and naming conditions; [NAIF credit guidance](https://naif.jpl.nasa.gov/naif/credit.html) asks users to acknowledge data providers. Archived source comments and the rules page are under `Scripts/ephemeris/pluto-attribution/`. No SPICE Toolkit code or runtime dependency is incorporated. The source reference for DE440 is Park et al., *The JPL Planetary and Lunar Ephemerides DE440 and DE441*, [DOI 10.3847/1538-3881/abd414](https://doi.org/10.3847/1538-3881/abd414).

## Representation and cost

Each immutable C array stores record-major, axis-major, ascending Chebyshev coefficients as C99 hexadecimal doubles. Each signed source coefficient is divided once by the exact adopted AU conversion, 149,597,870.7 km/AU. The evaluator sums all three arrays positively because the Sun array is already negated. Analytic differentiation returns AU/day; no finite-difference velocity, coefficient refit, resampling, runtime network, or CSPICE is involved. The source manifest records dimensions, complete source identities, grid selection, signs, units, generated-file sizes, and hashes.

| Compiled include | Step | Records | Coefficients per axis |
| --- | ---: | ---: | ---: |
| `pluto_barycenter.inc` | 32 days | 2,640 | 6 |
| `pluto_negative_sun.inc` | 16 days | 5,279 | 11 |
| `pluto_center_offset.inc` | 3 days | 28,151 | 16 |

There are **1,572,975 doubles, totaling 12,583,800 compiled data bytes**, before linker alignment or metadata. This is not a measurement of executable download size or resident memory. Development-only `MOONDEV1` binary excerpts in `.context/pluto-integration/` retain exact signed kilometer coefficients and 56-byte headers, totaling 12,583,968 bytes. They are not shipping resources. Production arrays have 40-day TDB guards `[2414980.5, 2499431.5]`; full intersecting original records are retained. Original polynomial seams are preserved, and no global C2 continuity claim is made.

## Verification results and limits

The full source replay checks **72,148 component states**, including every retained record boundary and midpoint within the guards and both sides of the PLU060 segment join. The fixed source parity limits are 0.00002 km per position component and 0.00002 km/day per velocity component. The largest AU-scaled position difference from independently evaluated SPK coefficients is **0.00000190735 km (1.91 mm)**; the largest velocity difference is **1.74623e-10 km/day**. A separate C compiler round-trip checks the exact IEEE-754 values of all 1,572,975 emitted constants. These checks establish representation/evaluator parity, not observational accuracy.

Seven supplemental split-TDB checks at the TT domain edges, adjacent representable TT values, and the PLU060 segment-join neighborhood pass with maximum composed position-component difference **2.38419e-6 km** and velocity-component difference **1.65019e-8 km/day**. A deliberate omission of the 9→999 component produces at least **2,131.29 km** of position error on those cases. That negative control protects body-center identity even though broad product tolerances might not detect the substitution.

| Comparison population | Count | Maximum angle error | Maximum absolute range error |
| --- | ---: | ---: | ---: |
| Fresh predetermined Horizons body-center samples | 128 | 1.63484e-10 arcmin | 6.69545e-9 ppm |
| Retrospective archived heliocentric samples | 259 | 1.59307e-10 arcmin | 7.23334e-9 ppm |

The fresh query requires target 999, center 10, geometric `NONE`, TT epochs, ICRF axes, body-center origin, AU/day units, and `plu060_merged` source headers for both target and Sun. Query, response, epoch plan, and report are hash-bound. These extremely small differences are expected because Horizons and this candidate share the same JPL solution family; they are independent evaluator comparisons, not independent observations or physical covariance estimates. The unchanged acceptance targets remain 1 arcminute, 100 ppm distance, and strictly less than 60 seconds for events.

All **18 retrospective Pluto alignments** were reevaluated by replacing Pluto with the candidate and interpolating the archived Earth reference vectors. Their maximum candidate difference is **0.0000573 seconds**, with a final numerical bracket width of 0.0001145 seconds; the old public API maximum remains **290.94994 seconds**. This isolates Pluto feasibility. It does not establish production event accuracy using AstronomyKit's existing Earth model. No new independent event population was acquired by this workstream.

## Exterior transition diagnosis

The approved interior must remain pure DE440+PLU060. A hard switch to the old model outside its endpoints would introduce position jumps: a diagnostic against legacy commit `ec134360afc24f91cbc2724bd81b2a925e110194` measures candidate-minus-legacy position norms of **158,477.9 km** at the lower edge and **436,147.3 km** at the upper edge. Velocity differences are approximately **2,104.0 and 2,068.8 km/day**. The archived legacy source SHA-256 is `40c9c17447a2725fd6002f7e450612e9ca149becf9617e71fa57fefca0f491ed`; the diagnostic plan and results are in `.context/pluto-integration/edge-plan.json` and `edge-report.json`.

A 32-day quintic transition entirely outside the approved interval fits the 40-day source guards and can make the transition weight and its first two derivatives match at its endpoints. The derivative of the transition weight must contribute to velocity. At the upper exterior transition, its contribution can reach roughly 25,600 km/day; the transition is a compatibility policy, not a physically qualified extension of the accepted date domain. This diagnostic does not certify continuity of the original SPK record seams or the legacy model itself.

## Reproduction

Checkout-only integrity requires Python's standard library, without the source SPKs or network:

```sh
python3 Scripts/ephemeris/verify-pluto.py
python3 -m unittest discover -s Scripts/ephemeris -p test_pluto_artifacts.py -v
```

All three tests pass: checkout provenance/structure, deliberately corrupted artifacts and guards, and complete C compiler constant round-trip. The compiler test is skipped if no C compiler is available.

Full source reproduction requires the two exact source SPKs at the paths in `generate-pluto.py`, plus the pinned development environment containing jplephem 2.24, pyerfa 2.0.1.5, and NumPy 2.5.3:

```sh
python3 Scripts/ephemeris/generate-pluto.py generate
python3 Scripts/ephemeris/generate-pluto.py check
python3 Scripts/ephemeris/verify-pluto-source-controls.py
```

The `check` action reproduces coefficients, C source, manifest, source parity, and frozen reference results without network acquisition. The original `acquire` action retains existing raw references; `report` refuses to overwrite an existing frozen report. Platform integration, production API residuals, optimized runtime cost, RSS, and hosted CI remain separate evidence.
