# Independent reference archive

This directory builds the offline fixtures used by `AuditValidationTests`. Tests never contact a network service. Frozen distance and model-diagnostic replay requires CPython 3.14.7, installed explicitly by the macOS workflow; ensure `python3 --version` reports that version before running the evidence commands. The exact reports are runtime-specific reproduction evidence, while the frozen distance allowances remain unchanged.

The separate distance archive supports `DistanceAccuracyTests`. `python3 Scripts/reference-data/distance-accuracy.py check` verifies its raw responses, query recipes, frozen characterization binding, allowances, generated fixture, and held-out report offline. `python3 -m unittest Scripts/reference-data/test_distance_accuracy.py -v` checks metadata corruption, query/response detachment, disjoint epoch selection, and refusal to grow a frozen allowance after a held-out failure. [DistanceAccuracyEvidence.md](../../Documentation/Migration/DistanceAccuracyEvidence.md) records the 1900–2100 TT scope, owner-selected 2× policy, distinct geometric and received-light observables, Sun-motion bridge, and remaining model-accuracy gaps. These engineering allowances belong to the new finite distance fixtures; the original observer diagnostics below retain their existing classification.

Run `python3 Scripts/reference-data/build-fixtures.py --refresh` to download the pinned Astronomy Engine source files and record fresh JPL Horizons responses. The refresh validates every download before writing any of them, and each query recipe records its response SHA-256 so an interrupted write cannot pass later verification as a matched pair. Run `python3 Scripts/reference-data/build-fixtures.py --check` to verify every archived source hash and confirm that the generated fixture and manifest are current. A normal generation run writes the fixture without downloading anything.

Run `python3 Scripts/reference-data/investigate-apparent-range.py --check` to compile the small C-core probe in a temporary directory and reproduce the source-bound diagnostic range residuals in `Documentation/Migration/apparent-range-investigation.json`. The report covers the 12 archived Moon, Mercury, Mars, and Pluto observer samples under JPL Horizons and Espenak-Meeus Delta T with and without Astronomy Engine's separate stellar-aberration correction. It records sampled observations and explicitly supplies no accuracy tolerance.

Run `python3 Scripts/reference-data/diagnose-polar-sunrise.py --check` to reproduce the isolated South Pole sunrise controls in `Documentation/Migration/polar-sunrise-diagnosis.json`. The command compiles the exact pinned and current C snapshots in temporary directories, disables the polynomial path, and exchanges the pinned nutation and VSOP boundaries independently. It reports signed event-time, altitude, slope, time-coordinate, and root-convergence results for the failing archived row and three neighboring polar events. The diagnostic does not change the 70.8-second allowance or rank the model variants for scientific accuracy.

Run `python3 Scripts/reference-data/investigate-polar-reference.py check` to replay the frozen independent JPL/USNO polar reference comparison offline. Full responses and response-bound query recipes are archived under `sources/polar-reference`; `acquire` refreshes them and `report` regenerates the comparison. [PolarSunriseIndependentEvidence.md](../../Documentation/Migration/PolarSunriseIndependentEvidence.md) explains the common-TT comparison, explicit horizon convention, remaining Earth-orientation differences and limited model-disposition evidence.

The JPL query recipes are stored beside each response under `sources/horizons`. Each recipe contains every API parameter plus `_responseSHA256`, which binds it to the adjacent response without sending that metadata field to Horizons. Observer queries use Earth center `500@399`, ICRF/J2000 equatorial coordinates, true ecliptic and equinox of date for the ecliptic columns, UT/UTC calendar output, airless apparent coordinates, and AU distance. Vector queries use geometric ICRF states, TDB, AU and AU/day, with Sun center for Chiron and Jupiter center for the Galilean moons. Each response records the service version, target identity, ephemeris source, frame, origin, units, time scale, and correction modes returned by Horizons. The generated fixture's ten-entry `provenance` catalog records those fields plus source domain, license, URL, and reproduction recipe for every source family.

The event sources are pinned to Astronomy Engine revision `865d3da7d8112bbc7911238052c6af4aaf877181`. That repository transformed published USNO, NASA GSFC, AstroPixels, and EclipseWise records into stable test tables. The archive retains the upstream MIT license, C engine, C validation harness, transformation scripts needed by the lunar records, and exact source hashes. The generator reads the 90-second lunar-quarter limit, 2-minute lunar-eclipse limit, 1.18-minute rise/set limit, compared time fields, chronological rise/set selection, and default Espenak-Meeus Delta T model from those pinned sources. It does not derive tolerances from AstronomyKit output.

- Seasons, Earth apsis times, and lunar phases come from pinned transformations of the USNO seasons and moon-phase APIs. The transformation serializes phase timestamps with `Z`, while the pinned C harness passes the calendar fields to `Astronomy_MakeTime` as a UT coordinate and compares TT values derived with its default Delta T model.
- Rise and set events come from the pinned transformation of the USNO yearly rise/set service. The [primary-source provenance investigation](../../Documentation/Migration/PolarSunriseReferenceSources.md) identifies the original yearly query and the parser's unchanged hour/minute serialization. The generator exports all 5,909 rows in source order across 17 body/location/year groups, rejects malformed or incomplete input, and preserves the harness's 16 continuous search streams. It treats each archived calendar timestamp as a UT coordinate, derives TT with the Espenak-Meeus model, independently advances the rise and set cursors, and selects the earlier TT event.
- Lunar nodes come from Fred Espenak's AstroPixels Node Passages of the Moon table and its pinned transformation.
- Global eclipse and planetary-transit records come from Fred Espenak's NASA GSFC catalogs. Lunar greatest-eclipse times and transit contacts use UT; global solar greatest-eclipse times use Terrestrial Dynamical Time as the catalog specifies. The pinned lunar harness compares the calculated and catalog UT fields directly.
- Local solar contacts come from the pinned EclipseWise table.
- Lunar and Earth apsis distances come from pinned Astronomy Engine validation tables whose original acquisition recipe is absent upstream. These records provide third-party parity evidence, not independent accuracy evidence; the JPL position archive and USNO Earth-apsis times provide compensating independent samples for distance-bearing calculations.

The source domains differ. The lunar-phase table contains one year every ten years from 1800 through 2100, and the archived fixtures sample 1800, 2000, and 2100. NASA catalogs publish UT lunar peaks and transit contacts, and dynamical-time global solar peaks, over the ranges named by each catalog page. The complete pinned rise/set table contains 17 regular and polar Sun and Moon groups from 1750 through 2050; the USNO service documents years 1700–2100 and apparent-horizon conventions that include standard refraction. Mercury and Venus transit tables cover their published catalog intervals. JPL Horizons supplies the explicitly requested epochs. Its observer `delta` field is apparent range with light-time aberration; the raw responses retain those values, but the generated fixture does not assert them because no cited source supplies a scientific tolerance that matches AstronomyKit's result. This leaves the independent-distance criterion in #81 open. Chiron remains an AstronomyKit addition, and its `0.01` AU component threshold is the existing repository sanity threshold rather than a scientific error bound.

NASA factual data is generally not subject to U.S. copyright; acknowledge NASA and do not imply endorsement. NASA eclipse records in this archive credit Fred Espenak and NASA GSFC. U.S. government USNO output is public domain. The transformed tables remain attributed to their named sources and Astronomy Engine; `sources/astronomy-engine-license.txt` contains the license that applies to the copied files and transformation code.

The harness limits are third-party parity thresholds, not scientific accuracy guarantees. Future civil UTC also depends on leap seconds that have not been announced. The two issue #110 readings, 93.35 seconds for the 2100 quarter and 160.36 seconds for the 2099 eclipse, result from treating the archived harness coordinates as civil UTC. The source-compatible TT and UT comparisons remain bounded; tests retain the civil readings only as unbounded finite diagnostics. The full rise/set comparison has 5,908 rows within the unchanged 70.8-second allowance and one active known failure: source line 2,923 is `75.985957542` TT seconds from the archived South Pole sunrise. Issue #124 tracks that public API result. The row remains in the test, and an unexpected pass requires the known-issue annotation to be revisited.

## Required-interval position and event pilot

[PositionEventValidationEvidence.md](../../Documentation/Migration/PositionEventValidationEvidence.md) reports the frozen 1900–2130 TT public-API pilot and its retained timing failures. `qualify-position-events.py` archives 29 independent vector series plus lunar apsis reference roots; `qualify-geometric-events.py` adds geometric lunar nodes and simultaneous heliocentric alignments using a pinned independent IAU2006 date-plane transform. The public Swift runner streams explicit-TT requests through `accuracy-batch`. These tools preserve historical fixture budgets and production models.

Historical pilot replay requires checkout `ec134360afc24f91cbc2724bd81b2a925e110194`, CPython 3.14.7, and the exact Swift toolchain, executable bytes, source hashes and reference environment recorded in `position-event-assessment.json` and `geometric-event-assessment.json`. The executable must occupy its recorded relative path, `.context/accuracy-qualification/build-runner/out/Products/Debug/AccuracyQualificationRunner`; the position pilot pins SHA-256 `e064aae8209f6b9fc7ad291ced6d09f607bc401d91754ba739bc4fbc90959cfa`. Restore that executable from the original evidence environment. A rebuild is usable only if its hash matches; rebuilding the current bundled model cannot reproduce the historical pilot or its lunar search diagnosis. Install dependencies only under `.context`; they are not shipping AstronomyKit dependencies. ERFA/NumPy wheel and loaded-binary hashes are recorded. Platform-specific wheels and compiler differences are provenance changes, not automatic evidence failures or permission to rewrite a frozen numerical report.

```sh
mkdir -p .context/accuracy-qualification
python3 -m pip install --target .context/accuracy-qualification/python-reference pyerfa==2.0.1.5 numpy==2.5.3
python3 -m pip install --target .context/accuracy-qualification/python-reference --no-deps jplephem==2.24
python3 -m pip download --only-binary=:all: --dest .context/accuracy-qualification/reference-wheels pyerfa==2.0.1.5 numpy==2.5.3
# Run these historical checks from the pinned checkout with its restored executable.
python3 Scripts/reference-data/qualify-position-events.py check --binary .context/accuracy-qualification/build-runner/out/Products/Debug/AccuracyQualificationRunner
python3 Scripts/reference-data/qualify-geometric-events.py check --binary .context/accuracy-qualification/build-runner/out/Products/Debug/AccuracyQualificationRunner
python3 Scripts/reference-data/diagnose-lunar-event-search.py check --binary .context/accuracy-qualification/build-runner/out/Products/Debug/AccuracyQualificationRunner
python3 -m unittest discover -s Scripts/reference-data -p 'test_*.py' -v
```

Current production replay uses the bundled runner and the separate [v2 public API assessment](../../Documentation/Migration/bundled-public-api-assessment-v2.json). The builder binds the live sources, Swift compiler version, package manifest and executable. The original [v1 assessment](../../Documentation/Migration/bundled-public-api-assessment.json) remains frozen. Run these commands from the current checkout after installing the reference environment above; they require the holdout plan's hash-pinned kernel and folded payload in `.context/accuracy-qualification`.

```sh
python3 Scripts/reference-data/build-bundled-runner.py
python3 Scripts/reference-data/qualify-bundled-ephemeris.py check
python3 -B -m unittest discover -s Scripts/reference-data -p 'test_*.py' -v
```

Exact `check` replay requires the compiler, executable and reference binary hashes recorded in v2. A different environment requires a separately named assessment; it does not authorize replacing either frozen report. The historical pilot checks above intentionally reject the current bundled executable.

The `acquire-positions`, `acquire-events` and geometric `acquire` commands resume complete response/query pairs and reject detached or incomplete pairs. They do not silently overwrite an archive. The `report` commands refuse an existing report; preserve original bytes before a separate source/provenance revalidation or candidate experiment. `check` replays every raw response/hash/recipe, public position/event result, frozen metric and source binding offline. Astronomical exceedances are retained results, not parser/test failures.

The separate [planetary apsis investigation](../../Documentation/Migration/PlanetaryApsisEvidence.md) uses geometric body-center range relative to the Sun body center across the complete 1900–2130 TT interval. Its sampling plan was frozen before acquisition. `acquire` fetches missing nonempty stages only, retains skipped refinements as inconclusive, and never overwrites a complete pair. The report preserves raw crossings, resolved orbit-scale candidates, additional-local classifications, every root failure, public pairings, and strict timing results. It does not qualify the family.

```sh
python3 Scripts/reference-data/build-accuracy-runner.py
python3 Scripts/reference-data/qualify-planetary-apsides.py check
python3 -B -m unittest Scripts/reference-data/test_planetary_apsides.py -v
```

The lunar candidate probe needs the exact official short kernel and development excerpt. Its [probe plan](../../Documentation/Migration/lunar-candidate-probe-plan.json) and JSON report pin inputs, segment identities and hashes. This downloads about 31 MiB into ignored scratch storage; no binary kernel is bundled in the shipping package.

```sh
curl --fail --location --output .context/accuracy-qualification/de440s.bsp https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp
PYTHONPATH=.context/accuracy-qualification/python-reference python3 -m jplephem excerpt --targets 301,399 1899/12/31 2131/1/2 .context/accuracy-qualification/de440s.bsp .context/accuracy-qualification/moon-earth-1900-2130.bsp
python3 Scripts/reference-data/probe-lunar-ephemeris-candidate.py check
```

The candidate probe uses previously observed cases and reports retrospective feasibility, not fresh acceptance, physical covariance, Swift integration or performance qualification. Preserve the DE440-versus-DE441 distinction and body-center contracts. No required timing threshold is loosened after an exceedance.

The separate native development probe folds identical Moon/Earth type-2 coefficient grids into a 6.28 MiB custom payload and compares a standalone optimized Swift evaluator with the original kernel at record boundaries/midpoints, guards and archived lunar cases. `report` builds the executable and records five local warm sequential microbenchmarks; preserve existing report bytes before regeneration. `check` verifies the exact deterministic source/executable/payload/parity fields; archived nonrepeatable timing/RSS observations are retained rather than claimed as newly replayed measurements. This does not integrate the candidate into public AstronomyKit APIs or satisfy shipping/platform/performance gates.

```sh
python3 Scripts/reference-data/probe-native-lunar-candidate.py report
python3 Scripts/reference-data/probe-native-lunar-candidate.py check
python3 -m unittest discover -s Scripts/reference-data -p 'test_native_lunar_probe.py' -v
```

## Selected bundled lunar follow-up

[LunarBundledPrototypeEvidence.md](../../Documentation/Migration/LunarBundledPrototypeEvidence.md) records the native TT/frame integration and fresh independent-reference holdout. The builder verifies sixteen official ERFA source/license/header files against a tracked exact byte lock before compiling its development-only source closure in scratch. The raw holdout archives are separately bound to the unchanged premeasurement plan. A report refuses overwrite; `check` verifies deterministic scientific/build fields while retaining archived nonrepeatable cost observations. Build and reference tooling are not shipping dependencies.

```sh
python3 Scripts/reference-data/build-integrated-lunar-probe.py
python3 Scripts/reference-data/qualify-lunar-candidate-holdout.py check
python3 -m unittest discover -s Scripts/reference-data -p 'test_integrated_lunar*.py' -v
python3 -m unittest discover -s Scripts/reference-data -p 'test_lunar_candidate_holdout.py' -v
```

The `acquire` action fetches missing pairs only, verifies their full recipes/response metadata and refuses incomplete/detached pairs. The frozen holdout positions and windows exclude the specified prior independent-reference catalog. Candidate event enumeration uses entire windows rather than reference-root seeds. Keep finite reference agreement distinct from physical covariance, continuous accuracy, public API/correction integration and #83 performance acceptance.
