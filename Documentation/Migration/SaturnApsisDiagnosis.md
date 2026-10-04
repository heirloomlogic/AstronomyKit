# Saturn body-center apsis timing failures

The six archived Saturn timing failures remain above the approved strict `<60 seconds` target. In these cases, the public search follows the production radial model within 0.66 seconds, and polynomial and full-series analytic roots agree at the probe's 0.0001-second bracket resolution. Changing the derivative or root tolerance cannot account for the archived errors of 9,036–356,597 seconds. The measured body-center versus Saturn-system-barycenter root shifts dominate all six errors, but a separate model residual remains: even the diagnostic barycenter comparisons exceed 60 seconds in every case. No production model or API contract changes in this investigation. #81 remains open.

The [diagnostic plan](saturn-apsis-diagnostic-plan.json) selects the six known failures from the [original assessment](planetary-apsis-assessment.json); this is attribution work, not a fresh accuracy holdout. The [complete diagnosis](saturn-apsis-diagnosis.json) binds the plan, implementation, tests, original assessment, compiler, executables and three new Horizons query/response pairs. The original raw references, failed cases, allowances, strict target and solar model decision remain unchanged.

## Center and model controls

All acceptance comparisons retain geometric Saturn body center `699` relative to Sun body center `10`, ICRF, TT, AU-D and `VEC_CORR=NONE`. The additional target `6` measures the Saturn-system barycenter for diagnosis only. [The Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html) distinguishes the system barycenter IDs from planet centers and permits TT vector tables; [the API documentation](https://ssd-api.jpl.nasa.gov/doc/horizons_file.html) describes the archived acquisition interface. Response metadata identifies `sat441l` for Saturn's body center and `DE441` for its system barycenter and the Sun. Every response is parsed against its exact recipe and SHA-256 receipt.

The query and response epochs are TT, and the public replay constructs explicit TT times with the JPL Horizons Delta T model; the internal root controls operate directly on days of TT since J2000. No civil UTC label is compared with a TT event. The Horizons manual bounds the periodic TT/TDB distinction at 0.002 seconds. A positive conversion factor between TT and TDB rates does not change a zero crossing; exact direct-rate scaling remains a separate requirement. These time conventions cannot explain the measured hour-to-day shifts.

A fixed 20-day grid with 0.125-day spacing surrounds each archived public event for both targets. Each directed crossing is retained, with a five-point cubic/quadratic diagnostic and its original one-second numerical allowance. A separate body-center precision control samples offsets of −0.01, −0.005, 0, +0.005 and +0.01 days around each archived independent root. These fresh body-center roots differ from the originals by at most 0.64 seconds. Cubic/quadratic differences describe interpolation behavior, not certified physical reference uncertainty.

The following signed differences are in seconds. The decomposition is `public − body center = (public − system barycenter) + (system barycenter − body center)`. The body-center column retains the original archived root; the center-shift column uses the fresh precision control, so displayed columns need not add exactly to the archived error.

| Archived public index | Public Julian date TT | Archived public − body center | Public − system barycenter | System barycenter − fresh body center |
| --- | ---: | ---: | ---: | ---: |
| 2 | 2425927.409191151 | −356,596.962 | +1,954.158 | −358,551.148 |
| 3 | 2431341.607300785 | +63,309.355 | +760.152 | +62,549.296 |
| 5 | 2442055.753279075 | +9,035.789 | −1,877.184 | +10,913.131 |
| 9 | 2463565.163950105 | −33,230.071 | +1,326.497 | −34,555.930 |
| 10 | 2468906.792163727 | −42,372.952 | +174.930 | −42,547.981 |
| 11 | 2474346.140402309 | +57,012.119 | −83.126 | +57,095.413 |

This decomposition attributes the dominant measured shift to the center difference while retaining the smaller model residual. It does not redefine the public observable as a system barycenter or establish a universal VSOP center/accuracy claim. Replacing the acceptance target with `6` would still leave all six cases above the strict target.

## Evaluation, derivative and search controls

The development-only C probe includes the current vendored implementation to access the exact retained VSOP87B tables. It evaluates their analytic spherical radial derivative directly, bypassing the polynomial path. A second analytic control differentiates the polynomial Cartesian norm before the ecliptic-to-equatorial rotation, matching the scalar distance evaluator. All six epochs are in qualified polynomial coverage. Both paths also use centered distance differences at steps of 0.001, 0.01 and 0.1 days. The fixed local scan checks root kind and one sign crossing; bisection narrows each bracket to at most 0.0001 seconds.

Polynomial and full-series analytic roots agree at that bracket resolution. Their offsets from the archived public events are −0.655, −0.103, +0.658, −0.155, +0.430 and −0.462 seconds in table order. Finite-difference roots differ from the corresponding analytic roots by at most 1.29 seconds. Some finite differences evaluate to exactly zero because of distance rounding; the report retains zero-slope evaluation counts. The small final bracket width is a solver diagnostic, not a bound on derivative quantization or physical timing accuracy. The probe also replays the public search from ten days before each event, retaining its kind and timing without substituting that replay for the archived failures.

These controls demonstrate that polynomial evaluation, the tested finite-difference stencils and local search precision cannot explain the six large errors. They do not rule out every possible implementation defect elsewhere in the event family. No demonstrated implementation repair removes these failures; selecting a replacement model while retaining body-center semantics remains separate work under the existing owner decision process.

## The 1929 pairing has additional identity uncertainty

For public index 2, the new body-center grid exposes three directed crossings near the event: apocenter, pericenter, apocenter. The original 16-day coarse grid recorded one crossing in this neighborhood. The additional cubic estimates lie approximately 387,269 and 105,874 seconds before the archived public event; their cubic/quadratic differences exceed the original one-second allowance, so they remain raw diagnostic crossings with inadequate numerical precision. The third crossing matches the retained archived reference.

This exposes a local completeness limitation in the original coarse discovery and limits its singleton orbit-scale classification for this pair. The original report and pairing remain historical evidence; the new report records the extra crossings explicitly. This task does not decide which body-center local extremum defines the public orbit-scale apsis, certify the extra roots, or change the production event identity. #81 tracks the center/model timing failures and this added identity limitation.

## Offline reproduction

```sh
python3 Scripts/reference-data/build-accuracy-runner.py
python3 -B -m unittest Scripts/reference-data/test_saturn_apsis.py Scripts/reference-data/test_planetary_apsides.py -v
python3 Scripts/reference-data/diagnose-saturn-apsides.py check
```

The new check rebuilds the diagnostic probe, verifies all source/query/plan hashes, and replays the complete original nine-body assessment. Every original scientific field matches: 3,380 pairs, six timing exceedances, 163 inconclusive roots and 62 unpaired public events. The original strict `qualify-planetary-apsides.py check` still rejects this locally rebuilt Swift runner because its executable SHA-256 differs from the archived executable; its compiler, platform, build manifest, scientific inputs and results match. The new diagnosis records both executable receipts and permits only that executable-hash difference when checking the original scientific replay. It does not change the original strict checker or its frozen report.

The diagnosis's own check compares all recorded fields except the commit-time Git revision and dirty-state receipt. Exact replay requires the recorded compiler, platform and source-bound executable receipts. Acquisition is an explicit separate action (`diagnose-saturn-apsides.py acquire`); checks use the archived files offline. This finite investigation does not establish continuous accuracy, complete event counts, release behavior or a production replacement policy.
