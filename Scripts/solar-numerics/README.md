# Native solar numerical tools

This is the first link of #94. It supplies native primitive measurements and Earth polynomial bounds for the later solar-altitude derivation. It does not certify the full altitude calculation or change `SolarAltitudeBounds.swift`. The public `SolarAltitudeObservation` still calls the C-backed horizon and keeps its existing constants until the integration and certificate are updated together.

## Reproduce

Use Python 3.10 or later and the package's Swift toolchain. The measurement runner supports macOS and Linux; the checked-in observations are macOS arm64, Apple Swift 6.4 only. It builds the package's test target, so `.dev-tooling` enables the normal formatter checks.

```sh
python3 -m venv .context/numerics-venv
.context/numerics-venv/bin/pip install -r Scripts/solar-numerics/requirements.txt
.context/numerics-venv/bin/python -m unittest discover -s Scripts/solar-numerics -v
python3 Scripts/solar-numerics/numerics.py --check
.context/numerics-venv/bin/python Scripts/solar-numerics/measure.py --configuration debug --output Scripts/solar-numerics/evidence/macos-arm64-debug.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure.py --configuration release --output Scripts/solar-numerics/evidence/macos-arm64-release.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure.py --recheck --output Scripts/solar-numerics/evidence/macos-arm64-debug.json
.context/numerics-venv/bin/python Scripts/solar-numerics/measure.py --recheck --output Scripts/solar-numerics/evidence/macos-arm64-release.json
```

`numerics.py` without `--check` regenerates `derived-earth.json`. `--bindings-only` checks source hashes without repeating the derivation. A changed bound source or data file fails the existing binding; regeneration records the new source and derivation together. Hash equality identifies the expressions evaluated; it does not prove that a changed expression is covered by an unchanged argument. Such a change still needs its mathematical derivation checked.

The measurement exporter reads explicit request and output paths from the runner's environment. It is disabled during ordinary tests. It executes `Engine.Time`, `Engine.DeltaT`, `Engine.EarthRotation`, `Engine.Nutation` and `Engine.Planet.earth` directly. C is still linked by the package, but none of those measured functions calls it. All native inputs and outputs are recorded as binary64 bit patterns. Rechecking re-executes the reference from those bits and verifies the source/data hashes; mismatched request IDs, lost input bits, duplicate/missing rows and altered reference values are tested failure cases.

## Derived polynomial terms

The Earth table is the native generated `PlanetPolynomialEarth.swift`, decoded directly from its little-endian binary64 payload. Those coefficients are exact rational numbers for this derivation. The script reads degree, segment width and coverage from the Swift data, checks their shape, and rejects exclusions rather than extending a polynomial argument over a series fallback.

For each component, `|T_k′(x)| ≤ k²` on `[-1,1]` gives speed no greater than `Σ k²|a_k| / (width/2)`. An exact sum of squares followed by an integer-square-root enclosure bounds the vector speed. Radius is evaluated with rational arithmetic at one-day nodes within each segment; every point of that segment is within half a day of a node, so widening by half its speed bound covers the whole segment. The endpoint values `Σa_k` and `Σ(-1)^k a_k` give each join difference exactly. Every square root is enclosed by rationals whose squares are checked, and conversion to binary64 rounds outward. The final partial segment is covered in full, which is conservative for the accepted span.

`derived-earth.json` records the exact rational bounds, outward binary64 values, domain and input hashes. These are bounds on the real-arithmetic piecewise polynomial's speed, radius and jumps. They exclude floating-point evaluation error, fit error against VSOP87B, frame rounding, libm, time conversion and light-time termination. No altitude constant is inferred from the sampled errors.

## Independent reference and attribution

`reference.py` evaluates model definitions at 80 decimal digits with mpmath 1.3.0. Selected polynomial/series, nutation, ERA and Delta T evaluations are repeated at 110 digits in the tests; this is a convergence check on those samples, not a proof of transcendental-function error.

- Delta T uses the [Espenak–Meeus NASA polynomials](https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html), with exact decimal coefficients. The reference covers calendar years 1800 through 2200. It follows the native contract's continuous Gregorian-year interpolation; NASA publishes the month-middle convention, not this interpolation. The JPL Horizons option is the library's held-Espenak–Meeus approximation, not an independently published JPL model. It holds UT at 17 × 365.24217 days.
- Earth Rotation Angle uses the IAU 2000 definition as one extended-precision linear angle reduced after evaluation. It does not copy the production split-day arithmetic.
- IAU 2000B uses the existing 77 ERFA-derived coefficient rows, the published linear Delaunay arguments and fixed planetary offsets. The reference sums at extended precision without the production argument reductions or binary64 summation. Its check value and tolerance are ERFA's `t_nut00b`, already recorded in `PublishedOrientation.swift`. Existing ERFA notices apply.
- VSOP87B uses the native generated Earth coefficients, interpreted as exact shipped binary64 values. It evaluates the defining power/trigonometric series with extended-precision summation, rather than production's compensated sum. Its J2000 check is the IMCCE `vsop87.chk` Earth row at the existing 1e-10 tolerance. Source URLs and pinned hashes remain in `Scripts/planet-data/manifest.json`; the table provenance and Astronomy Engine MIT notice remain in `THIRD_PARTY_NOTICES`.
- Chebyshev evaluation uses `Σ a_k cos(k acos(x))`, independent of production's Clenshaw recurrence. This measures evaluation of the shipped fit; it does not claim that the fit is an exact representation of the planetary theory.

The independent Python implementation is AstronomyKit code. mpmath is a development dependency, not bundled model data or a product dependency. Its authors and BSD license are linked in `THIRD_PARTY_NOTICES`.

## Recorded coverage and remaining work

Each configuration records 162 rows: a 33-point coverage grid, six fallback epochs, four polynomial seams with adjacent doubles, nine Delta T piece boundaries with adjacent doubles, and the held-model boundary, for both models. Files contain all requests, native bits, extended values, signed differences, inverse residuals, source/data hashes, compiler identity and process measurements. There is no error threshold inferred from these maxima. `gitHead` is the checkout base at measurement time; source hashes identify the evaluated working-tree candidate precisely.

The Debug and Release reports differ by one ULP in nutation longitude at the 2101 fallback sample for both models. Their sampled maxima are identical; the reports retain the individual results.

The process timing and RSS include SwiftPM and the test runner in a fresh invocation after the build. They are not library-only latency or retained library memory. Release library build time and library artifact size are reported separately on the PR.

Link 2 still needs the full geometric-altitude reference, precession/observer/horizon composition, civil conversion and inverse derivations, sensitivities, light-time termination and iteration-flip cases, complete coverage/fallback/seam grids, exclusion and paired-altitude identity checks, and the public constant/article update. The current article's historical C measurements do not become native evidence because these primitive checks pass.
