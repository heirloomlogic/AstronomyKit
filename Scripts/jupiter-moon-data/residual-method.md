# Galilean-moon residual replay

This harness covers proposal step 1 of [#254](https://github.com/heirloomlogic/AstronomyKit/issues/254). It measures the current truncated L1.2 engine against all 104 existing Horizons rows: 26 each for Io (501), Europa (502), Ganymede (503), and Callisto (504), relative to Jupiter's body center (599). It leaves the production model, archived responses, fixture values, and existing tolerances unchanged. #254's jup365 replacement, transition, size, latency, and km-level acceptance remain outstanding.

From a committed implementation, run:

```sh
python3 Scripts/galilean-residuals.py --capture
python3 -m unittest Scripts/test_galilean_residuals.py -v
python3 Scripts/galilean-residuals.py --check
```

`--capture` runs `swift test --no-parallel --filter EngineGalileanResidualCaptureTests` and validates the candidate before replacing `residual-evidence.json`. It rejects uncommitted changes to its bound sources and checks that source hashes and HEAD stay unchanged during capture. The artifact records the actual capture revision and Swift toolchain, embeds the raw native vectors, and includes their canonical JSON SHA-256. `captureSourceSHA256` is checked against the complete historical owner inventory and file contents in that Git commit; a missing commit, tree object, omitted owner, or changed digest fails. `sourceSHA256` binds the current replay implementation. Only the Python checker and its tests may differ from the historical capture inputs; a changed native source, fixture, generator, or helper requires a new native capture. The source bindings cover the complete native Swift source inventory, the capture and replay code, the manifest and generator, the test's fixture/time helpers, the fixture archive, and all eight original Horizons responses and their queries. No archive is fetched or rewritten. `--check` runs offline on the preserved capture within a Git checkout containing its capture commit; it does not run Swift or claim a fresh native execution. The macOS and Linux checker jobs fetch full history so this commit is available locally. Before capture, the native filesystem inventory must match the committed HEAD inventory, including owners removed by staged or unstaged deletions.

## Epoch, origin, and axes

The eight preserved `<moon>-vector.json` and `<moon>-domain-vector.json` responses supply geometric states (`VEC_CORR=NONE`), Jupiter center `500@599`, ICRF axes (`REF_SYSTEM=ICRF`, `REF_PLANE=FRAME`), AU and AU/day, and the archived JDTDB epochs. The replay checks the complete query recipe, response SHA-256, response target/center/frame/unit/correction headers, exact dates and columns, and every vector's projection into `reference-fixtures.json`. Each moon has three calendar anchors and 23 domain rows. The existing bounded subset is 22 rows per moon between JD 2426545.0 and 2476545.0; four per moon carry no accuracy allowance. Captures use a fixed canonical order: moon order 501–504, each moon's calendar anchors followed by its domain rows. Omission, duplication, and reordering fail replay.

The native epoch is TT days since J2000. Starting from archived TDB days since J2000, three fixed-point evaluations solve `TT = TDB − (TDB−TT)(TT)/86400`. The test captures this TT, the geocentric Fairhead–Bretagnon/JPL offset, and `dTDB/dTT`. The Python replay evaluates the 787 bound terms and JPL adjustments independently, with a sum of powers rather than the native Horner evaluation. Binary64 checks allow 2e-11 day in TT, 2e-15 second in the offset, and 3e-16 in the rate; these are replay arithmetic checks, not physical accuracy allowances. The native function reads TT only; its test time's UT field is a placeholder.

Native vectors are on EQJ axes. Python rotates each Horizons ICRF position and velocity to EQJ with an independent row-matrix construction of the IAU 2006 J2000 frame bias, using the four Fukushima–Williams angles documented by `Engine.FrameBias`. This matches the existing Horizons test convention. It does not resolve whether the original L1.2 fit's stated J2000 frame should instead be treated as ICRF; that ambiguity is separate from this residual measurement.

## Separate measurements

`positionErrorKm = |nativePositionEQJ − rotatedHorizonsPosition| × 149597870.7`.

The native API documents its returned vector as AU per TT day. Its Keplerian velocity is computed from the instantaneous orbital elements and gravitational parameter; it is not the derivative of the time-varying L1.2 position. To align the documented units, the report multiplies Horizons' rotated AU/TDB-day velocity by `dTDB/dTT`, then records `keplerianVelocityErrorKmPerTTDay = |nativeKeplerianVelocity − alignedHorizonsVelocity| × 149597870.7`. This scaling aligns the comparison units and does not turn the native vector into a position derivative. The raw vectors and `unscaledVelocityErrorKmPerDay` are also retained so the rate correction can be inspected independently.

The report contains one position residual and one returned-velocity residual per archived row, plus separate per-moon maxima and exact worst JDTDB epochs for all 26 rows and the bounded 22-row subset. Ties use the first row in canonical capture order. It reapplies the existing 9e-4 relative tolerance only where the fixture already carries it. The rows outside that subset remain observations without a new accuracy gate.

Python tests start from independently constructed states with known 1 km position and 2 km/TT-day velocity offsets. They check exact maxima and epochs, wrong targets/centers/frames/clocks, malformed vectors, omitted/duplicate/reordered records, wrong-moon and swapped-axis numerical controls on bounded rows, source ownership/digest mutation, false or unavailable capture revisions, staged and unstaged deletions of committed native owners, response metadata and recipe mutations with updated digests, fixture drift, and changed reported metrics. These checks establish replay integrity over this inventory. They do not establish an unsampled bound, isolate the physical cause of the residual, reproduce the former uncommitted full-L1.2 37-day-grid comparison, or qualify a jup365 replacement.
