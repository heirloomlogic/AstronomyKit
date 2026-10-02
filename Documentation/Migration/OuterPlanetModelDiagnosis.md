# Uranus and Neptune model diagnosis

This diagnosis follows [DistanceModelFollowup.md](DistanceModelFollowup.md) and tracks [model-fitness issue #119](https://github.com/HeirloomLogic/AstronomyKit/issues/119). It compares the raw complete VSOP87B series with the primary archived DE200 numerical solution and frozen DE441 references. It supplies a quantitative radial decomposition, independent arithmetic checks, and explicit frame, epoch, unit, and center diagnostics. The product's useful maximum radial/vector errors remain undecided; none of these numbers is an acceptance limit or a replacement-model selection.

## Predetermined diagnostic epochs

The separate [epochs.json](../../Scripts/reference-data/sources/distance/model-diagnostics/outer-planets/epochs.json) was written before these reference queries. It contains 17 uniformly spaced TT Julian dates over JD 2415020.5–2488070.5, plus exact J2000 JD 2451545.0: 18 epochs per body. The complete selection rule, freeze timestamp, and file SHA-256 `aa87d839bbbfc60f758ee82c4f3444adb92099f4c2dc4985f60acf731c85fe98` are archived. The diagnostic does not read characterization, heldout samples, distance budgets, or acceptance reports, and these dates were not selected by measured residuals. Its finite sampled maxima do not bound the full date interval.

## Signed radial attribution

Let `R` be the radius from the independent full VSOP87B sum, `D200` the heliocentric radius of the system barycenter from DE200, and `D441` the corresponding DE441 radius. At each common TT instant, `R − D441 = (R − D200) + (D200 − D441)`. This is an exact scalar decomposition apart from floating-point rounding; rotations do not change any of these radii. All comparisons in this table use the modern fixed AU `149597870.7 km`, with the historical DE200 AU sensitivity reported separately.

| Maximum absolute residual on 18 epochs per body | Uranus (km) | Neptune (km) |
| --- | ---: | ---: |
| Full raw VSOP87B minus DE200 system-barycenter radius | 537.802 | 3,643.865 |
| DE200 minus DE441 system-barycenter radius | 8,687.502 | 8,516.241 |
| Full raw VSOP87B minus DE441 system-barycenter radius | 8,454.394 | 8,959.687 |
| Full raw VSOP87B minus returned modern body-center solution radius | 8,808.663 | 9,297.231 |

The independently maximized rows above occur at different dates and must not be added. The actual signed components at each body's largest raw-minus-DE441 radial residual are:

| Body | JDTT | Raw minus DE200 (km) | DE200 minus DE441 (km) | Raw minus DE441 (km) |
| --- | ---: | ---: | ---: | ---: |
| Uranus | 2469808.0 | +233.109 | −8,687.502 | −8,454.394 |
| Neptune | 2460676.75 | −1,987.248 | −6,972.439 | −8,959.687 |

The DE200-to-DE441 radial difference supplies most of the signed residual at both of those dates, with partial cancellation for Uranus. Neptune also retains a substantial raw-series-to-DE200 contribution. These measured contributions establish that changing the fitted reference solution is material; they do not identify which changed observations, masses, dynamics, or fitted parameters caused the DE200-to-DE441 difference. The raw-to-DE200 remainder is a measured difference between complete analytical and numerical trajectories, not proof of a particular missing analytic term or a mistaken coefficient archive.

## Independent summation and implementation checks

[outer-planet-diagnostic.py](../../Scripts/reference-data/outer-planet-diagnostic.py) reads the original archived fixed-column VSOP87B coefficients directly, validates them against `Scripts/model-data/manifest.json`, checks each header's counts and every term's coordinate/power/rank, and evaluates `T = (JDTT − 2451545)/365250`. It sums every longitude, latitude, and radius term with `math.fsum` and direct powers. It uses neither the generated C arrays nor production polynomial evaluators.

A separate 60-decimal-digit calculation converts the original decimal coefficient strings directly into `mpmath` numbers and evaluates the trigonometric and power series independently. Its complete decimal results are archived in `high-precision.json`. Maximum binary64-versus-60-digit radius disagreement is **0.000000531 km** for each body; longitude disagreement is below `1.8e-15 rad`, and latitude disagreement is below `1.2e-17 rad`.

The official [IMCCE VSOP87 check file](https://ftp.imcce.fr/pub/ephem/planets/vsop87/vsop87.chk), SHA-256 `f8fa52449262be05a22a96840c1acbad0b35c8999e00b5c0477ba8a91a67a51a`, supplies another independent reference. All 10 published VSOP87B check epochs for each body, spanning J2000 through earlier millennia, match all three spherical coordinates within the check file's 10-decimal-place rounding. The largest radius difference is `4.955e-11 AU`, below the printed half-unit rounding allowance. This checks the file/version, coordinate interpretation, epoch scaling, summation, and angular wrapping against the author's own published outputs.

The existing local diagnostic probe is compiled without changing production code and evaluated at the 18 new epochs. Raw-minus-local radius disagreement is at most **0.000004783 km** for Uranus and **0.000002657 km** for Neptune. Transforming raw spherical coordinates with the published VSOP-to-FK5 matrix reproduces the local vector within **0.000006623 km** and **0.000007889 km**. This excludes arithmetic and local coefficient/polynomial implementation differences as material explanations at these samples, while leaving the scientific model's residual visible.

## Frame, epoch, unit, and center diagnostics

The primary [NAIF DE200 SPK archive](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/a_old_versions/de200.bsp) is 56,780,800 bytes, SHA-256 `4b1021ceb01033f7d512b15dbe63b7b2421f118104e127374a85537ad0d336f9`. Its inspected segments explicitly identify Uranus system barycenter `7`, Neptune system barycenter `8`, and Sun `10`, relative to solar-system barycenter `0`, in native **DE-200 frame 14**. The extraction subtracts target and Sun at the same epoch, with no aberration correction. Segment summaries and kernel comments are included with the small extracted states; the large SPK remains in `.context` and has a hashed download recipe.

VSOP87B uses the dynamical ecliptic and equinox J2000. [Bretagnon and Francou (1988), equation (1)](https://articles.adsabs.harvard.edu/pdf/1988A%26A...202..309B) supplies the DE200 equatorial relation: inertial obliquity `23°26′21.4091″` and equatorial equinox angle `−0.0930″`. The diagnostic applies that explicit orthogonal transformation to obtain a comparison in native DE200 axes. Maximum raw-minus-DE200 vector difference is **1,185.040 km** for Uranus and **7,736.504 km** for Neptune. The published angles have finite precision, so these are not frame-transform error certificates.

SPICE's built-in `pxform('DE-200', 'J2000', 0)` returns an **identity matrix** here. Consequently, requesting SPICE J2000 does not independently measure or remove the physical DE200-to-ICRF orientation bias. [NAIF's frame documentation](https://naif.jpl.nasa.gov/pub/naif/toolkit_docs/C/req/frames.html#ICRF%20vs%20J2000) explains that ICRF interpretation follows the underlying data's frame. The report's `de200AxesMinusDE441ICRFVectorKm` and `rawDE200AxesMinusDE441ICRFVectorKm` explicitly retain this limitation: they are numerical differences across physical axes whose alignment has not been independently established. Their respective maxima are 18,740.828/46,367.450 km and 18,931.103/49,788.053 km for Uranus/Neptune. They do not provide physically frame-resolved vector causal attribution. The published VSOP-to-FK5 convention and the explicit VSOP-to-DE200 convention differ by up to 87.298 km for Uranus and 131.360 km for Neptune at these distances; that sensitivity also does not affect the scalar radial decomposition.

DE200 interpolation uses **TDB**, while the diagnostic epochs and Horizons requests use **TT**. SPICE `unitim` converts TT seconds from J2000 to TDB using archived `naif0012.tls` and CSPICE N0067. The extraction separately evaluates the incorrect interpretation of those TT seconds as TDB: its maximum vector effect is **0.000562 km** for Uranus and **0.000468 km** for Neptune. This sampled sensitivity is too small to explain the kilometre-scale model residuals. The raw VSOP sum retains the documented TT argument rather than silently changing the series convention to match the numerical kernel.

The primary [DE200 ASCII header](https://ssd.jpl.nasa.gov/ftp/eph/planets/ascii/de200/header.200) records the historical astronomical unit **149597870.66 km**. Using this value for the raw VSOP radius instead of the modern fixed AU changes it by at most **0.804 km** for Uranus and **1.213 km** for Neptune. The resulting maximum raw-minus-DE200 radial discrepancies are still **537.020 km** and **3,642.657 km**. The unit change is measurable and does not account for the large residual.

All modern barycenter recipes use Horizons commands `7`/`8`, Sun origin `500@10`, TT epochs, geometric ICRF equatorial vectors, and `AU-D`; both target and Sun source tags are **DE441**. The separate body-center recipes use commands `799`/`899` and return **ura184_merged**/**nep098_merged** solutions. At these samples, the center-solution-minus-barycenter radial difference reaches 1,181.528 km for Uranus and 508.390 km for Neptune; corresponding vector differences reach 4,855.208 km and 2,142.185 km. These are differences between returned fitted trajectories, not isolated physical satellite-center offsets: separate planetary/satellite fits, and sometimes separate Sun fits, are involved. Merely selecting those returned body-center trajectories does not remove the large radial residual. A consistently anchored satellite-kernel decomposition remains a separate unresolved task.

## Evidence and reproduction

All small reference bytes, parameters, source identifiers, version information, hashes, extracted states, decimal independent sums, and per-epoch results are under [sources/distance/model-diagnostics/outer-planets](../../Scripts/reference-data/sources/distance/model-diagnostics/outer-planets). `report.json` binds the executable diagnostic, coefficient manifest/data, production C/header inputs, existing probe, and every archived reference/recipe by SHA-256. The offline check verifies recipes and source metadata, recomputes every row and summary, and rejects changed hashes, epochs, target/center/solution semantics, nonfinite numbers, caveats, or report structure. Its `0.0001 km`/`2e-12 rad` comparison allowances address compiler/libm reproduction only; they are not model-accuracy requirements.

Run the offline reproduction and evidence-contract tests from the workspace root using only Python's standard library and a C compiler:

```sh
python3 Scripts/reference-data/outer-planet-diagnostic.py check
python3 -m unittest discover -s Scripts/reference-data -p 'test_outer_planet_diagnostic.py' -v
```

The acquisition dependencies are isolated from the library and offline checker. To reproduce DE200 extraction and the independent high-precision calculation, create a temporary environment, install the recorded versions, fetch and verify the primary SPK, and run the separate actions:

```sh
python3 -m venv .context/outer-planet-diagnostic/venv
.context/outer-planet-diagnostic/venv/bin/pip install spiceypy==8.2.0 mpmath==1.4.1 numpy==2.5.3
python3 Scripts/reference-data/outer-planet-diagnostic.py fetch-de200
.context/outer-planet-diagnostic/venv/bin/python Scripts/reference-data/outer-planet-diagnostic.py extract-de200
.context/outer-planet-diagnostic/venv/bin/python Scripts/reference-data/outer-planet-diagnostic.py high-precision
python3 Scripts/reference-data/outer-planet-diagnostic.py check
```

`acquire-horizons` is a separate explicit network action. It uses the frozen dates and archives full response bytes plus recipes; a reacquisition can change acquisition timestamps or returned solution versions and therefore changes evidence hashes. Keep the original archive when reproducing this report. `report` explicitly writes a new diagnostic report after intentional evidence changes; it never writes acceptance data.

## Remaining scientific decisions

The complete raw series, independent sums, primary historical reference, explicit modern barycenters, time conversion, and AU sensitivity now establish a sampled scalar attribution. They do not establish product fitness, a continuous error bound, physically frame-resolved DE200-to-ICRF vector attribution, or the contribution of each observational/dynamical change between ephemerides. A repair or replacement still requires independently chosen product limits, a frame/center contract, fresh characterization, and a newly independent holdout. This diagnosis does not change any production model or frozen acceptance policy.
