# Bundled Moon and Pluto production integration

The shared C engine now uses immutable JPL coefficient data for Moon and Pluto throughout calendar 1900–2130 TT: JD [2415020.5,2499391.5). Positions, analytic states and event searches use the same models. No runtime download or initialization callback is required. Current Sun/Earth models and the public accepted time ranges are retained. Outside the required interval, 32-day quintic transitions join the bundled and legacy models with their position and velocity derivatives; those exterior transitions are numerical continuity measures, not physically qualified ephemerides.

The Moon data represents 301 relative to 399 from DE440s. Pluto is body999relative the Sun, composed from the DE440 Pluto-system barycenter, negative DE440 Sun and the PLU060 body-center offset. Time conversion and J2000 bias use a pinned ERFA subset. See [lunar source and integration evidence](LunarBundledIntegrationEvidence.md), [Pluto source evidence](PlutoBundledRepairEvidence.md), and the licenses/source locks they link. Each generated hexadecimal C coefficient survives compilation as the exact intended binary64 value. The arrays contain 6,586,632 lunar bytes and 12,583,800 Pluto bytes, totaling 18.28 MiB.

The original diagnostics and reference populations are preserved in commit `ec134360`. [The new public API assessment](bundled-public-api-assessment.json) records 7,511 positions and 233 archived events, plus the 128-position/52-event lunar candidate holdout replay through production APIs. All angular samples meet 1 arcminute; all 4,921 geometric/none radius samples meet the approved body-specific distance limits. All 73 archived lunar events and 18 Pluto alignments meet the strict 60-second target: worst lunar apsis 0.640 second, lunar node 0.977 second, Pluto alignment 0.928 second. The 52 holdout events have worst difference 0.634 second. Counts, identities, directions and ordering match the reference populations. All 6,216 non-Moon/Pluto sampled vectors match their original values exactly.

One unchanged Neptune alignment differs by 60.243447 seconds. It fails the nominal strict 60-second target and remains inconclusive under the previously frozen 1-second numerical reference envelope. The 1,904 corrected-distance diagnostic exceedances remain visible; their correction conventions differ from the geometric distance policy. These finite populations do not prove continuous or observational accuracy. Other event families, UTC/Earth-rotation accuracy and the South Pole sunrise issue [#124](https://github.com/heirloomlogic/AstronomyKit/issues/124) remain outside this repair. General accuracy qualification [#81](https://github.com/heirloomlogic/AstronomyKit/issues/81) stays open.

Old exact production snapshots cannot serve as expected outputs of a repaired model. [Versioned regression evidence](BundledRegressionSnapshots/README.md) retains the original reproduction source and 5,035-row rate archive, lists 67 changed Moon/Pluto literal occurrences, and separately captures 795 updated Moon/Pluto rate rows. Every numerical comparison budget is unchanged. Unaffected bodies retain their original expectations. Historical diagnostic scripts explicitly replay their byte-pinned baseline instead of replacing their reports with repaired outputs.

[Local production cost evidence](bundled-production-costs.json) uses five new process trials per operation with 100,000 distinct TT epochs in an optimized Swift executable. It measures full public state calls, including `AstroTime` construction. Measured latency varied under other host workloads; process RSS is about 15 MiB for Moon and 20 MiB for Pluto. This is descriptive evidence from one macOS host; device costs, hosted RSS attribution and the pure-Swift migration performance gates in [#83](https://github.com/heirloomlogic/AstronomyKit/issues/83) remain separate. The historical performance archive is verified as historical evidence and does not qualify this larger shipping model against its old budgets.

## Reproduction

Checkout-only data integrity needs Python and a C compiler, without the original kernels or reference wheels:

```sh
python3 Scripts/ephemeris/generate-lunar-bundle.py --check
python3 Scripts/ephemeris/verify-pluto.py
python3 -m unittest Scripts/ephemeris/test_pluto_artifacts.py -v
python3 -m unittest Scripts/reference-data/test_bundled_public_api.py -v
swift test --no-parallel
```

For public API replay, install the exact reference wheels described in [reference tooling](../../Scripts/reference-data/README.md) under `.context/accuracy-qualification/python-reference`. The raw Horizons response/query pairs are tracked. Building the runner binds the executable to every C/Swift input and coefficient include; source or executable drift fails before assessment. The `check` command compares against the exact recorded executable report. Rebuilding on another toolchain may change binary identity and requires a separately named candidate report, preserving the original.

```sh
python3 Scripts/reference-data/build-bundled-runner.py
python3 Scripts/reference-data/qualify-bundled-ephemeris.py check
python3 Scripts/ephemeris/measure-production.py
```

Full coefficient regeneration additionally requires the exact DE440s/PLU060 kernels and pinned scientific dependencies listed in the individual source evidence. Large original kernels are development inputs and are not shipped in the package.

## Local validation

The shipping Swift suite passes 713 tests across 188 suites with the existing known polar sunrise issue. Reference tooling passes 101 Python tests; the migration tests pass after deriving the frozen oracle population from its named baseline tree. Generated data integrity, complete compiler constant round-trips, cache positive/negative controls, 30 sanitizer seed inputs and 17,622 binary64/binary128 solar states pass unchanged numerical ceilings. Strict lint passes for the shipping sources/tests, model runner and new cost runner. Hosted CI and independent review are recorded in the pull request.
