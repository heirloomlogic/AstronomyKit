# Native Pluto DE441 integration

`Engine.Pluto` accepts the engine's TT ±1,461,000-day range. Its DE440/PLU060 physical-center state now spans the complete verified source coverage, with 32-TDB-day interior blends described in the [complete PLU060 qualification](PLU060-QUALIFICATION.md). Outside those blends, the Float64 shared-node cubic represents the Pluto system barycenter. The unavailable full-range center correction and physical-center velocity accuracy remain unqualified.

## Representation and transformations

The tables contain 91,314 Pluto-barycenter intervals of 32 days and 182,627 Sun intervals of 16 days. Each shared endpoint stores six little-endian Float64 values: ICRF X/Y/Z kilometers followed by analytic X/Y/Z kilometers per TDB day. Their decoded payloads total 13,149,264 bytes (12.54 MiB), up from 6,898,944 bytes over the former range. The [all-record source certificate](de441-evidence.json) bounds the heliocentric representation error by 0.2352431692 km and 0.1343837357 km/TDB day. The slightly larger enclosures come from scanning the wider range; the independent one-arcminute target is unchanged.

`Engine.PlutoDE441` reconstructs each cubic, evaluates its analytic derivative, subtracts Sun from Pluto, converts kilometers to AU, multiplies the derivative by `Engine.TDB.rate`, and applies the fixed ICRF-to-EQJ frame bias. The blend derivative includes w′ times the center-minus-barycenter position difference. The barycentric API adds the existing `Gravity.MajorBodies` Sun and keeps that API's origin convention. It does not use DE441's global SSB origin.

The source selection adds one day before the lower observation endpoint, plus the existing 2.2e-8-day TT/TDB margin. Whole records give joint Pluto/Sun coverage [−1461016.5, +1461015.5) TDB days. Internal retarded Pluto evaluations require a valid observation, matching Delta T models, finite scales, and emission no later than reception. Corrected aberration also backdates Earth; a Pluto-only evaluator permits the existing VSOP87B series and analytic derivative up to one TT day before the public lower bound. Public Earth queries retain their strict range. The lower-endpoint Horizons sample has native light time 0.198689 days, inside both margins.

Solar angle, pair longitude with the Sun, and elongation retain the Sun's separate light-time restriction at the exact lower engine endpoint. Their tests still pass at the former Pluto endpoint. Searches and composed angles are not promised to accept every engine endpoint.

## Validation

The [direct-source fixtures](de441-native-fixtures.json) contain 4,320 body states and 72 heliocentric states. Selection includes uniform records, every candidate's worst-bound records, the full-span frozen epochs and neighboring records, and x = −1, −0.5, 0, 0.5, 1 inside each selected body record. The fixture pins the source-evidence digest.

Swift tests gate these states against the upward-rounded source representation enclosures and check TT/TDB and frame transformations, 48 integrated outer samples, all 273,939 adjacent body-record boundaries, both strict TT endpoints, invalid times, and blend derivatives. All 15 archived target-9 directions and 29 target-999 center/blend epochs retain their original public-route limits. [Observer qualification](OBSERVER-QUALIFICATION.md) covers 41 epochs, including the expanded physical-center transitions and both exact engine endpoints; all three direction comparisons retain the 1′ limit. These sampled results do not qualify unsampled physical-center accuracy or continuous full-range velocity/event accuracy.

## Reproduction and measurements

```sh
python3 Scripts/assess-pluto-de441.py --cache .context/issue-252/ranges --plu060 .context/issue-252/plu060.bsp --artifacts .context/issue-252/candidates --check
python3 Scripts/generate-pluto-de441.py --binaries .context/issue-252/candidates
python3 Scripts/generate-pluto-de441.py --reference-fixtures --cache .context/issue-252/ranges
python3 Scripts/generate-pluto-de441.py --check
python3 -m unittest Scripts/test_assess_pluto_de441.py Scripts/test_generate_pluto_de441.py Scripts/test_record_pluto_de441_evidence.py -v
python3 Scripts/record-pluto-de441-evidence.py --capture
python3 Scripts/record-pluto-de441-evidence.py --check
```

The recorder requires a committed source tree. It runs the Pluto implementation checks in fresh Debug and Release processes, runs separate outer-cold and center-cold Release measurements, records the generated-source, object, executable, and decoded-payload sizes, binds the capture revision and complete Engine source inventory, validates the finished document, and replaces the evidence file atomically.

The opt-in measurement uses a fresh process. Setting `PLUTO_MEASUREMENT_CENTER=1` selects TT −72000 for a separate cold center-table decode; the default cold date measures the outer DE441 tables. It measures first use at TT −766,524.75, then 2,000 outer states over −766,500 to +766,500, 2,000 central states from −30,000 in 30-day increments, and 2,000 states over the complete engine range. The artifact retains the historical legacy-model baseline and its original workload description; the added full-engine workload has no baseline counterpart.

On the recorded arm64 macOS host, outer first use took 8.15 ms. In a separate fresh process, center first use at TT −72000 took 20.16 ms and reached 120,553,472 bytes peak RSS. The outer-first process's 2,000-state outer, central, and full-engine workloads took 58.18 ms, 37.35 ms, and 36.93 ms, with peak RSS 151,273,472 bytes after all loops. The complete center payload is 21,768,120 bytes; its generated Swift totals 29,252,565 bytes, C-string sections 29,250,912 bytes, and Release objects 58,537,728 bytes. The linked test executable is 154,493,328 bytes. These shared-host measurements include test-process and linker overhead; they do not isolate the model extension's cost or predict device performance.

[The measurement artifact](de441-native-evidence.json) records current source hashes, host, timings, peak RSS, generated-source and compiled-object sizes, linked test-executable size, direct-source residuals, seam maxima, and archived residuals. The historical baseline includes cold legacy integration and comes from a separate run. It is not an isolated measurement of this range extension's overhead. Generated source, objects, executable, decoded payload, and process RSS describe different storage stages; none is an application download-size or device-performance estimate. No size, speed, radial, or velocity ceiling is inferred from these observations.

The apparent-place integration refresh binds the complete Engine Swift module and the shared distance archive reader used by the retained validation tests. Non-Moon astrometric range comparisons use the untouched raw Horizons ranges; the legacy fixed-Sun adjustments remain in the archive. The module-wide digest set is conservative, not a minimal per-body dependency graph. Offline validation rejects a missing engine or distance-fixture binding as well as stale named hashes. Current native captures and measurements are recorded separately from the preserved historical baseline.
