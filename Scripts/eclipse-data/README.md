# Native eclipse evidence

The lunar records qualify the shared native shadow geometry and lunar-eclipse search added for issue #93. The separate global-solar records below cover its second link. Public eclipse facades, local solar circumstances and transits remain outside these native qualifications.

`native-captures.json` records Debug and Release results for six NASA lunar eclipses, a fresh-process Release workload of one cold search followed by 99 next-event searches, build receipts, object sizes, the test executable size, the tested base revision and the toolchain. `native-evidence.json` checks the existing peak and duration allowances, independently derives residuals from each captured native peak and source time, verifies Debug/Release agreement, and binds the resource observations to their exact call counts. The resource values describe one host and establish no portable ceiling.

The selected NASA catalog cases cover 1800, 2000, 2001 and 2099. The pinned NASA Observer's Handbook 2001 page supplies exact UT peaks for a total, partial and penumbral eclipse. Their phase durations come from the modern Five Millennium Catalog, which identifies Danjon's shadow-enlargement method and publishes its greatest-eclipse coordinate in TD; the fixture does not reinterpret that TD coordinate as UT. NASA lunar eclipse magnitude is a fraction of the Moon's diameter immersed in a shadow. It is retained with that meaning and is not relabeled as disc-area obscuration.

NASA SVS pages 4953 and 5672 directly publish 99.1% and 96.3% Moon-disc obscuration at greatest eclipse in 2021 and 2026. Assuming the printed percentages were rounded to the nearest 0.1 percentage point, the inclusive comparison intervals add and subtract 0.0005 from the printed fractions; inclusive endpoints avoid assuming a tie rule. Both pages come from one publisher and the same disclosed DE421/LOLA model family, and neither page publishes its exact rounding rule, lunar and shadow radii, or full-precision area algorithm. The intervals are inferred print intervals rather than NASA uncertainty bounds or an engine tolerance. The native geometry evaluates NASA's published Danjon angular shadow equations on a tangent plane at the Moon's geocentric distance. Agreement inside these narrow intervals shows consistency with the printed values under the stated rounding assumption; it does not establish exact replication of the SVS algorithm.

Run the offline checks:

```sh
python3 Scripts/reference-data/build-fixtures.py --check
python3 -m unittest Scripts/reference-data/test_build_fixtures.py Scripts/test_eclipse_event_evidence.py
python3 Scripts/record-eclipse-event-evidence.py --check
swift test --filter EngineEclipseEventTests
```

To reproduce the host observations, run the complete Debug and Release suites with `ECLIPSE_EVENT_OUTPUT` set to separate output directories, save each build log as `full-debug.log` or `full-release.log`, then run `EngineEclipseEventTests.resources` in a fresh Release process with `ECLIPSE_EVENT_MEASUREMENT=1`, `ECLIPSE_EVENT_OUTPUT` set to a third directory and `--skip-build`. Pass the parent capture directory to `record-eclipse-event-evidence.py --capture` after all commands succeed.

## Native global solar eclipses

The second #93 link adds the internal global search. `global-references.json` is rebuilt by `Scripts/capture-global-solar.py` from the pinned NASA catalog and RP1301 sources under `Scripts/reference-data/sources/global-solar/`. Every new publisher response has an adjacent query recipe; the capture tool downloads and validates the complete candidate set before changing canonical files. `global-captures.json` and `global-evidence.json` record Debug/Release outputs, source-derived timing/location/area comparisons and host costs. The recorder checks input identities, TT/UT relations, partial nil/NaN representation, finite central fields, angular-radius-to-area relations, source allowances and cross-configuration agreement. All directly used engine, public input, fixture, test, parser and recorder sources are bound by digest.

The original three global events retain 453.6 seconds and 0.247 degrees. Four additional catalog cases cover 2014 non-central annular, 2043 non-central total, 2023 hybrid with total geometry at greatest eclipse and 2025 partial. A hybrid is a path classification, not a promise of totality at its peak. The finite umbral/antumbral cone can intersect Earth when its axis misses the geoid; the public C shortcut that misclassifies both non-central events remains tracked in [#96](https://github.com/heirloomlogic/AstronomyKit/issues/96#issuecomment-6079064119).

Solar-only geometry uses the historical 959.63 arcsecond Astronomical Ephemeris semidiameter at one au, published in [NASA/JPL's constants report, Table 9](https://ntrs.nasa.gov/api/citations/19690001472/downloads/19690001472.pdf), converted with the sine of that angle and the engine's au. The umbral lunar radius is NASA's k2=0.272281 times the Earth equatorial radius; penumbral discovery uses the modern catalog's k1=0.272488. These are scoped solar-model choices. The qualified lunar-shadow constants remain unchanged. Neither the modern IAU nominal solar radius nor C's 14-meter classification bias establishes RP1301's convention.

RP1301 uses DE200/LE200, k1=0.2725076 and k2=0.272281. Its Table 4 directly publishes annular obscuration 0.8895 at 17:10 and 17:15 UT on 1994-05-10. Both native area results fall in [0.88945,0.88955], conditional on nearest-four-decimal printing; the publisher supplies no rounding rule or uncertainty bound. These source epochs use the report's fixed 59.5-second Delta T, not the contemporary model's conversion.

The finer G0 comparison remains a qualification gap: RP1301 prints a topocentric diameter ratio of 0.94314 at greatest eclipse, implying area [0.943135²,0.943145²] under nearest-five-decimal rounding. The native physical angular-disc area is below that interval. The evidence retains the actual value, signed residual and failed interval comparison separately from the passing Table 4 samples. The [report's algorithm page](https://eclipse.gsfc.nasa.gov/SEpubs/19940510/text/ephemerides.html) cites the Explanatory Supplement, whose classical magnitude formula uses observer-plane penumbral and umbral cone radii; RP1301 does not disclose revised algebra for its distinct k1/k2 values. That omission does not turn the observed mismatch into agreement, and no radius was fitted to it.

The 1986-10-03 boundary discriminator is also diagnostic: the source catalog prints H and magnitude 1.0000, while RP1301's lunar-limb discussion describes a beaded-annular observation. At the printed TD epoch, k2 plus the historical solar semidiameter produces a small positive mean-limb umbra and a ratio about 1.0000164, hence total under this smooth-disc model. The retained C radii and its 14-meter bias do not resolve the limb discrepancy. Rounded 1.0000 alone cannot supply an exact peak-kind oracle. No lunar limb profile or observed beading is modeled here.

`radius-vectors.json` and `radius-comparison.json` retain the bounded four-encoding discriminator at the two Table 4 epochs, G0 and the 1986 source epoch. `Scripts/global-solar-radius-probe.swift` emits the native vectors; `Scripts/assess-global-solar-radii.py` independently computes central surface angles and the radius comparison. `diameterRatioSquared` can exceed one in a total case; `areaObscuration` is capped at one by full containment, not by C's annular cap. The reported signed umbra is the straight-cone diagnostic, not an asserted lunar-limb observable.

```sh
python3 Scripts/capture-global-solar.py --check
python3 Scripts/assess-global-solar-radii.py --check
python3 -m unittest Scripts/test_global_solar.py
python3 Scripts/record-global-solar-evidence.py --check
swift test --filter EngineGlobalSolarEventTests
```

Set `GLOBAL_SOLAR_OUTPUT` to separate Debug/Release directories for source captures. The recorder expects those directories as `debug/` and `release/`, completed build receipts as `full-debug.log` and `full-release.log`, and a fresh-process Release `EngineGlobalSolarEventTests.resources` run under `GLOBAL_SOLAR_MEASUREMENT=1` in `resources/`. `record-global-solar-evidence.py --capture <directory>` validates the complete recording before publishing either JSON file. These measurements establish no portable performance ceiling. Public APIs, local circumstances and transit searches remain separate work.

The TD calendar fixture helper treats printed TD fields as epoch-day arithmetic. Its former UTC conversion shifted the 2024 reference by 4.824 seconds and the 2099 reference by 131.632 seconds; correcting it changes the source residuals, not the native trajectory or tolerances. Both callers, the public global audit and the native global source test, now use the corrected helper. The recorded build receipts accompany final affected-suite recaptures; the author receipt separately retains complete Debug/Release passes from before this test-input correction.
