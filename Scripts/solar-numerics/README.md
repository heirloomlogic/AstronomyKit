# Native solar numerical tools

These tools derive the native solar-altitude partial arithmetic budget, certify finite exact-reference light-time return for supported public scalar inputs, and retain independent higher-precision measurements. `SolarAltitudeObservation` constructs native time and uses the ordinary native Sun horizon for named models. The budget excludes polynomial/frame/libm and Delta T evaluation altitude error; coarse guards used to classify supported inputs remain separate.

## Reproduce

Use Python 3.10 or later and the package's Swift toolchain. The measurement runner supports macOS and Linux; the checked-in observations are macOS arm64, Apple Swift 6.4 only. It builds the package's test target, so `.dev-tooling` enables the normal formatter checks.

```sh
python3 -m venv .context/numerics-venv
.context/numerics-venv/bin/pip install -r Scripts/solar-numerics/requirements.txt
.context/numerics-venv/bin/python -m unittest discover -s Scripts/solar-numerics -v
python3 Scripts/solar-numerics/numerics.py --check
python3 Scripts/solar-numerics/certify_light_time.py --check
python3 Scripts/solar-numerics/derive_altitude.py --check
.context/numerics-venv/bin/python Scripts/solar-numerics/measure.py --configuration debug --output Scripts/solar-numerics/evidence/macos-arm64-debug.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure.py --configuration release --output Scripts/solar-numerics/evidence/macos-arm64-release.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure.py --recheck --output Scripts/solar-numerics/evidence/macos-arm64-debug.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure.py --recheck --output Scripts/solar-numerics/evidence/macos-arm64-release.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure_altitude.py --configuration debug --output Scripts/solar-numerics/evidence/altitude-macos-arm64-debug.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure_altitude.py --configuration release --output Scripts/solar-numerics/evidence/altitude-macos-arm64-release.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure_altitude.py --recheck --output Scripts/solar-numerics/evidence/altitude-macos-arm64-debug.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure_altitude.py --recheck --output Scripts/solar-numerics/evidence/altitude-macos-arm64-release.json
```

`numerics.py` without `--check` regenerates `derived-earth.json`. `--bindings-only` checks source hashes without repeating the derivation. A changed bound source or data file fails the existing binding; regeneration records the new source and derivation together. Hash equality identifies the expressions evaluated; it does not prove that a changed expression is covered by an unchanged argument. Such a change still needs its mathematical derivation checked.

The measurement exporter reads explicit request and output paths from the runner's environment. It is disabled during ordinary tests. It executes `Engine.Time`, `Engine.DeltaT`, `Engine.EarthRotation`, `Engine.Nutation` and `Engine.Planet.earth` directly. C is still linked by the package, but none of those measured functions calls it. All native inputs and outputs are recorded as binary64 bit patterns. Rechecking requires the complete canonical request sequence, re-executes the reference from those bits and verifies the source/data hashes; mismatched request IDs, lost input bits, duplicate/missing rows and altered reference values are tested failure cases.

## Derived polynomial terms

The Earth table is the native generated `PlanetPolynomialEarth.swift`, decoded directly from its little-endian binary64 payload. Those coefficients are exact rational numbers for this derivation. The script reads degree, segment width and coverage from the Swift data, checks their shape, and rejects exclusions rather than extending a polynomial argument over a series fallback.

For each component, `|T_k′(x)| ≤ k²` on `[-1,1]` gives speed no greater than `Σ k²|a_k| / (width/2)`. An exact sum of squares followed by an integer-square-root enclosure bounds the vector speed. Radius is evaluated with rational arithmetic at one-day nodes within each segment; every point of that segment is within half a day of a node, so widening by half its speed bound covers the whole segment. The endpoint values `Σa_k` and `Σ(-1)^k a_k` give each join difference exactly. Every square root is enclosed by rationals whose squares are checked, and conversion to binary64 rounds outward. The final partial segment is covered in full, which is conservative for the accepted span.

`derived-earth.json` records the exact rational bounds, outward binary64 values, domain and input hashes. These are bounds on the real-arithmetic piecewise polynomial's speed, radius and jumps. They exclude floating-point evaluation error, fit error against VSOP87B, frame rounding, libm, time conversion and light-time termination. No altitude constant is inferred from the sampled errors.

`certify_light_time.py` reconstructs the exceptional arrival strips and their UT, TT and Date binary64 scalar candidates, then proves strict stopping inequalities with outward rational intervals. `derived-light-convergence.json` records 49,888 candidate incidences in 66 strips and 364 certified batches, with no unresolved singleton. The real-input cycling regression must remain unresolved: a real cycling point does not become a representable public input by rounding it. The source/data-checked localization constants and the complete finite coverage are part of the artifact, not inferred from the measured grid. This certificate depends on `derived-earth.json` also passing its full rational check.

`derive_altitude.py` reads actual Swift Delta T, frame, observer, ERA and generated-table expressions. `derived-altitude.json` records the partial terms and separate classification guards; `SolarAltitudeBounds.swift` is generated with outward constants and exact binary64 gap classifications. The coarse native-radius guard bounds normalization/Clenshaw/fixed-matrix rounding enough to establish the delay enclosure, but its position error is not added to the public altitude budget. All three derivation commands without `--check` regenerate their own artifacts. The altitude command also regenerates the Swift constants. Source-expression mutation tests and complete-coverage deletion tests exercise the check paths.

## Independent reference and attribution

`reference.py` evaluates model definitions at 80 decimal digits with mpmath 1.3.0. Selected polynomial/series, nutation, ERA and Delta T evaluations are repeated at 110 digits in the tests; this is a convergence check on those samples, not a proof of transcendental-function error.

- Delta T uses the [Espenak–Meeus NASA polynomials](https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html), with exact decimal coefficients. The reference covers calendar years 1800 through 2200. It follows the native contract's continuous Gregorian-year interpolation; NASA publishes the month-middle convention, not this interpolation. The JPL Horizons option is the library's held-Espenak–Meeus approximation, not an independently published JPL model. It holds UT at 17 × 365.24217 days.
- Earth Rotation Angle uses the IAU 2000 definition as one extended-precision linear angle reduced after evaluation. It does not copy the production split-day arithmetic.
- IAU 2006/2000A nutation uses the generated ERFA-derived rows, 678 luni-solar and 687 planetary, the two IAU 2006 adjustment factors, and the published polynomial and linear arguments that `iauNut00a` reads. The reference sums at extended precision without the production argument reductions or binary64 summation. Its check value and tolerance are ERFA's `t_nut06a`, already recorded in `PublishedOrientation.swift`. Existing ERFA notices apply.
- VSOP87B uses the native generated Earth coefficients, interpreted as exact shipped binary64 values. It evaluates the defining power/trigonometric series with extended-precision summation, rather than production's compensated sum. Its J2000 check is the IMCCE `vsop87.chk` Earth row at the existing 1e-10 tolerance. Source URLs and pinned hashes remain in `Scripts/planet-data/manifest.json`; the table provenance and Astronomy Engine MIT notice remain in `THIRD_PARTY_NOTICES`.
- Chebyshev evaluation uses `Σ a_k cos(k acos(x))`, independent of production's Clenshaw recurrence. This measures evaluation of the shipped fit; it does not claim that the fit is an exact representation of the planetary theory.

The independent Python implementation is AstronomyKit code. mpmath is a development dependency, not bundled model data or a product dependency. Its authors and BSD license are linked in `THIRD_PARTY_NOTICES`.

## Recorded coverage and limits

The primitive report in each configuration records 162 rows: a 33-point coverage grid, six fallback epochs, four polynomial seams with adjacent doubles, nine Delta T piece boundaries with adjacent doubles, and the held-model boundary, for both models. Files contain all requests, native bits, extended values, signed differences, inverse residuals, source/data hashes, compiler identity and process measurements. There is no error threshold inferred from these maxima. `gitHead` is the checkout revision at measurement time; source hashes identify the evaluated working-tree candidate precisely.

The Debug and Release reports differ by one ULP in nutation longitude at the 2101 fallback sample for both models. Their sampled maxima are identical; the reports retain the individual results.

The full-altitude reports differ in 11 altitude results: ten supported rows differ by at most four ULP, and one excluded fallback row differs by eight ULP. Their sampled maxima are identical. Paired-altitude identity is asserted within a configuration, not between configurations.

The process timing and RSS include SwiftPM and the test runner in a fresh invocation after the build. They are not library-only latency or retained library memory. Release library build time and library artifact size are reported separately on the PR. `evidence/production-macos-arm64.json` retains the production build/section-size logs, standalone public client source and command, call trials and process RSS, with the retained link-1 artifact for context.

The full-altitude report in each configuration records 1,320 requests: the coverage/fallback/adjacent-seam grid at six observers under both models, three backdating-flip neighborhoods, and 96 civilDate cases. The native exporter records the actual light-time trace, full native altitude, and either a public observation with its budget or an explicit unsupported reason. It checks that supported observations retain the native time pair and ordinary altitude bits. The reference evaluates both the recorded pair and the exact public input; its inverse selects the solution near the recorded UT and reports a missing mathematical inverse explicitly. Request field `value` is UT/TT days when `scale` is `ut`/`tt`, or Foundation seconds since 2001-01-01 when `scale` is `date`.

`solar_reference.py` composes the IAU 2006 elementary precession rotations, IAU 2006/2000A nutation, the complete 33+1 complementary terms, IAU mean sidereal polynomial, IERS ellipsoid and a direct local vector projection. Precession, mean sidereal time and complementary terms retain the existing SOFA definition checks/tolerances; the underlying ERFA-derived data and notices are unchanged. The 2005 backdating discrepancy is retained at 80/110 digits and as a public integration regression. These implementations use published definitions and native data; no C output is a reference or input to the derivation.

The full-altitude `--recheck` also builds/runs a fresh Swift export in the saved report's Debug or Release configuration. It compares every accepted/rejected outcome, rejection reason and complete budget with that replay. Historical and fresh altitude bits are each checked against their own native calculation, without requiring cross-platform altitude equality. A failed native replay fails the recheck; saved outcome self-consistency alone is insufficient. The independent higher-precision model comparison still re-executes from the historical native bits.

The article `SolarAltitudeNumerics.md` gives the returned-iterate modulus, finite-convergence localization, civil/inverse/ERA expressions, frame/observer sensitivities and runtime classification assumptions. The public budget still excludes whole classes of numerical error. A measured difference below that partial sum is a sample observation, not evidence that excluded errors vanish or that the sum is a complete accuracy certificate.
