# Native lunar-eclipse evidence

This archive qualifies the shared native shadow geometry and lunar-eclipse search added for issue #93. It does not switch the public eclipse facades, qualify solar eclipses or transits, or close #93.

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
