# Finite independent distance acceptance

The recommended next steps in [DistanceAccuracyLiterature.md](DistanceAccuracyLiterature.md) now have executable evidence: independent geometric radius and received-light range characterization, frozen body-specific engineering allowances, disjoint held-out comparisons, and offline Swift assertions. This is partial work for #81, not continuous astronomical certification or completion of the migration gate.

## Scope and policy

The interval is `1900-01-01 <= TT < 2101-01-01`. There are 131 characterization epochs: one predetermined random epoch in each of 128 equal date strata, plus the opening endpoint, the final second of 2100, and J2000. A separately seeded holdout has 128 different stratified epochs and six predetermined transit, opposition, station, and lunar-apsis leads. Neither seed nor epoch selection uses engine residuals. The 19 body/observable combinations yield 2,489 characterization comparisons and 2,546 held-out comparisons. The holdout does not densely cover every orbit, geometry, polynomial boundary, or integrator boundary.

The owner chose a 2× characterization margin before characterization. The frozen rule is `allowedErrorKm = roundUpToMetre(2 * max(characterizationMaximumKm, literatureScaleFloorKm) + approximationAllowanceKm + alignmentAllowanceKm)`. The approximate VSOP heliocentric scales in the literature review supply planetary floors; planetary geocentric floors also include Earth's approximate scale. Adding these scales is a policy floor, not propagation of a published vector bound. Moon and Pluto receive no VSOP floor. Sun's Earth-relative floor uses Earth's scale. The approximation allowance is 0.001 km. The alignment allowance is 1 km for received-light comparisons and zero for geometric comparisons. These additions are separate engineering allowances, not formal libm or continuous interpolation bounds.

[`distance-characterization.json`](distance-characterization.json) records raw-input and engine hashes, scalar and vector residuals, full-series versus production approximation differences, maxima, 95th percentiles, sampled range extrema, and worst epochs. [`distance-allowances.json`](distance-allowances.json) binds the unchanged characterization bytes and records each budget's components. The holdout was acquired and evaluated only after that file was written. No allowance was increased in response to holdout results. The generator refuses characterization refresh, characterization regeneration, or another freeze once the policy file exists; the negative control proves an acceptance failure leaves its budget unchanged.

## Reference conventions

The core characterization and holdout have 56 raw responses and 56 hash-bound recipes under `Scripts/reference-data/sources/distance/`; six additional center-diagnostic pairs are in its `diagnostics` subdirectory. Requests use explicit TT, ICRF, AU/day, and body centers. Returned ephemeris tags are retained individually: DE441 for the Sun, Earth, Moon, Mercury and Venus, and satellite solutions for other planet centers. This pins returned reference data rather than assuming that every body center uses one planetary kernel. The recipes use the [Horizons file API](https://ssd-api.jpl.nasa.gov/doc/horizons_file.html), which supports larger discrete epoch lists without a long GET URL. Tests never download reference data.

Geometric heliocentric radius compares `distanceFromSun(at:)` with the norm of Sun-centered `NONE` vectors at identical TT. Vector residuals are separately reported as diagnostics: the local FK5 matrix and Horizons ICRF are not identical, and radial agreement does not certify vector accuracy. The local Earth series is Earth, not EMB. Outer-planet and Pluto center-model semantics remain an explicit limitation; a large empirical body-center allowance cannot resolve that model contract. See [DistanceReferenceConventions.md](DistanceReferenceConventions.md) for primary-source provenance and the distinction between body centers and barycenters.

For received-light range, the reference starts with Earth-centered `LT` vectors and the production assertion explicitly uses `.none` for stellar aberration. AstronomyKit backdates its heliocentric target but fixes Earth at reception. Independent Sun barycentric positions at reception and Horizons emission time expose the origin difference: `matchedVector = horizonsLTVector - (sunAtEmission - sunAtReception)`. Its norm is the convention-aligned reference; the original Horizons range and the signed adjustment are retained. The largest held-out Sun-motion range adjustment is 340.233 km, so silently absorbing it into a model tolerance would conflate different observables.

This bridge evaluates the target at Horizons' emission epoch rather than solving the fixed-Sun light-time equation again. Its first-order remainder estimate is `abs(rangeAdjustmentKm) / c * (relativeSpeedKmPerSecond + 60)`, where 60 km/s is an explicit conservative engineering speed supplement, not a certified interval bound. Emission TT is rounded to 10⁻⁸ day and obtained by subtracting the returned light-time days from reception TT. The separate 1 km alignment allowance covers these retained approximations empirically; the largest held-out estimate is 0.106 km. Both characterization and holdout reject an estimate above the allocation. The evidence does not claim an exact barycentric Horizons apparent-range limit or cover the public default `.corrected` result.

Moon validation instead requests Earth-centered `NONE` and compares instantaneous geometric lunar range, matching the production special case. Its Brown-derived provenance and lack of a published kilometre bound remain separate from VSOP. Pluto's custom integrator has its own measured allowances; TOP2013 accuracy is not transferred to it.

## Results

All 2,546 held-out comparisons pass the frozen allowances. The table reports kilometres; geocentric rows use the conventions above.

| Body | Observable | Characterization maximum | Held-out maximum | Frozen allowance |
| --- | --- | ---: | ---: | ---: |
| Mercury | Heliocentric | 4.228 | 3.857 | 8.458 |
| Mercury | Geocentric | 20.017 | 17.540 | 41.035 |
| Venus | Heliocentric | 1.619 | 1.572 | 5.412 |
| Venus | Geocentric | 8.383 | 6.611 | 17.768 |
| Earth | Heliocentric | 3.322 | 2.862 | 7.482 |
| Mars | Heliocentric | 7.100 | 7.359 | 45.589 |
| Mars | Geocentric | 69.763 | 46.658 | 140.528 |
| Jupiter | Heliocentric | 277.861 | 314.591 | 555.724 |
| Jupiter | Geocentric | 429.705 | 450.140 | 860.411 |
| Saturn | Heliocentric | 697.034 | 694.935 | 2001.109 |
| Saturn | Geocentric | 746.421 | 803.978 | 2009.589 |
| Uranus | Heliocentric | 8881.262 | 8834.768 | 17762.526 |
| Uranus | Geocentric | 9051.266 | 8989.147 | 18103.533 |
| Neptune | Heliocentric | 9306.030 | 9309.502 | 18612.061 |
| Neptune | Geocentric | 10142.876 | 10275.995 | 20286.753 |
| Pluto | Heliocentric | 213749.676 | 213584.008 | 427499.354 |
| Pluto | Geocentric | 214735.297 | 216737.981 | 429471.595 |
| Moon | Geocentric geometric | 14.344 | 15.300 | 28.689 |
| Sun | Geocentric | 3.322 | 2.862 | 8.482 |

The largest sampled production-versus-complete-series vector difference is below 0.000034 km, far below these independent residuals. Mars, Jupiter, Saturn, Neptune, Pluto, and Moon have some held-out maxima above characterization maxima, demonstrating the role of the declared margin. Passing this finite regression policy does not establish product fitness: roughly 9,000 km outer-planet and 214,000 km Pluto radial discrepancies warrant independent model investigation before promising accurate ranges. An angular tolerance cannot settle that question.

[DistanceModelFollowup.md](DistanceModelFollowup.md) records further diagnostics without changing the policy. Untouched vendored upstream Pluto already has a 213,557.979 km radial maximum on the same characterization epochs; the largest pointwise local-versus-upstream radial change is 403.207 km. Separate archived center and barycenter requests at the worst Uranus, Neptune, and Pluto epochs leave roughly 8,279 km, 8,998 km, and 213,631 km radial discrepancies. Their source solutions differ, so this is not a pure satellite-offset decomposition. The note includes source/query hashes, reproduction commands, unproven hypotheses, and a staged investigation plan.

## Reproduction and remaining work

Run the existing offline checks without refreshing or refreezing any tolerance:

```sh
python3 Scripts/reference-data/distance-accuracy.py check
python3 -m unittest Scripts/reference-data/test_distance_accuracy.py -v
swift test --filter DistanceAccuracyTests
```

The initial staged acquisition was `refresh-characterization`, `characterize`, `freeze`, `refresh-heldout`, then `accept`, using the same script. The committed frozen policy deliberately prevents repeating the first three actions. The current source hashes must match characterization provenance; a later implementation change needs explicit evidence review rather than automatic replacement of the historical baseline. The macOS workflow verifies the archive, source binding, and held-out report offline. Swift assertions also run in the ordinary macOS and Linux suites; this session provides local macOS evidence only.

The parser rejects changed TT/frame/origin/unit/correction metadata, incomplete coverage, nonfinite states, and detached query/response hashes. Swift negative controls reject wrong units, observer selection, date, distance sign, and use of the default aberration range. Existing position and event negative controls remain responsible for frame-direction and event-selection errors; scalar range is invariant under an exact frame rotation.

Remaining work is to resolve outer-planet and Pluto model-center semantics, investigate the large independent radial discrepancies, validate exact barycentric apparent-range behavior if the API intends to promise it, establish meaningful range-rate checks, and obtain denser geometry and boundary coverage if the intended product contract requires it. Dates outside 1900–2100, future civil UTC, the default aberration norm, continuous maxima, and whole-domain accuracy are not established. Issue #81 remains open; no production numerical model or public API changed here.
