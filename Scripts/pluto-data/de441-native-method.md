# Native Pluto DE441 integration

`Engine.Pluto` retains the physical-center DE440/PLU060 state bit for bit from 1900-01-01 through 2131-01-01 TT. Outside its existing 32-day blends, it uses the Float64 shared-node cubic qualified by [the feasibility assessment](DE441-ASSESSMENT.md). The accepted interval remains TT ±766,525 days. The legacy integrated model and its segment cache remain available through `modelState` for diagnostics; the native state route no longer populates that cache.

The outer state represents the Pluto system barycenter. It omits the physical Pluto-center offset. The available PLU060 evidence covers 1800–2199, and the center's omitted velocity reaches 0.024273 km/s at archived reference dates. Neither the full-range center correction nor physical-center velocity accuracy is established by this integration. The public C-backed path remains owned by #96, with applicable search work under #92. Issue #190 remains open.

## Representation and transformations

The two source grids are preserved: 47,909 Pluto-barycenter intervals of 32 days and 95,817 Sun intervals of 16 days. Each endpoint stores six little-endian Float64 values: ICRF X/Y/Z kilometers followed by analytic X/Y/Z kilometers per TDB day. Neighboring cubics share the same stored position and rate node. Together the payloads occupy 6,898,944 bytes. `generate-pluto-de441.py` verifies both payloads against the reviewed [source evidence](de441-evidence.json) and owns only `Gravity/Generated/DE441`; the legacy Pluto generator owns its direct `Generated/*.swift` files. The lifecycle regression runs both generators and checks all outputs before and after normal regeneration, including removal and recreation of the new output directory.

`Engine.PlutoDE441` reconstructs each cubic, evaluates its analytic derivative, subtracts the Sun state from the Pluto-system state, converts kilometers to AU, multiplies the derivative by `Engine.TDB.rate`, and applies the fixed ICRF-to-EQJ frame bias. TT-to-TDB conversion uses the existing `Engine.TDB.offsetSeconds`. The blend derivative includes w′ times the center-minus-barycenter position difference. The barycentric API retains its existing `Gravity.MajorBodies` origin by adding that model's Sun to the heliocentric result; it does not silently switch to DE441's global solar-system barycenter.

## Validation

[Direct-source fixtures](de441-native-fixtures.json) contain 4,305 body states, selected from each body's uniform full-span grid, every candidate's worst-bound records, and the frozen full-span/transition epochs with their adjacent records. Each selected body record is evaluated at x = −1, −0.5, 0, 0.5, 1. The fixture also contains heliocentric states at all 72 frozen epochs from link 1. It pins the exact source-evidence digest. Python 3.11 and 3.14 produce identical fixture bytes from the previously verified cache; the qualification scan and source evidence remain unchanged.

The Swift tests check both bodies against the established 0.234914 km and 0.134200 km/TDB-day sum-of-bodies representation bounds, rounded upward from the source certificate. They also exercise the TT/TDB and frame transformation, 48 eligible integrated outer samples, all 143,724 adjacent body-record boundaries, both strict TT endpoints, invalid times, existing blend derivative/continuity checks, and the original archived-reference tolerances. Central DE440 tests retain their bitwise routing, 1 km position, and 1e-8 relative velocity checks. All 15 archived far-range native barycenter directions now meet their original 1′ target, so those native known-issue wrappers are removed. The public and physical-center acceptance gaps remain explicit.

The extra boundary limits are arithmetic regression checks at the scale of the decoded Float64 source experiment. They are not new physical velocity or resource requirements. Broad fixture comparisons are sampled checks of the Swift implementation; the all-record source polynomial certificate comes from link 1. Full-range absolute physical state/event accuracy remains unqualified.

## Reproduction and measurements

```sh
python3 Scripts/generate-pluto-de441.py --binaries .context/issue-190/candidates
python3 Scripts/generate-pluto-de441.py --reference-fixtures
python3 Scripts/generate-pluto-de441.py --check
python3 -m unittest Scripts/test_assess_pluto_de441.py Scripts/test_generate_pluto_de441.py -v
PLUTO_MEASUREMENT_OUTPUT="$PWD/.context/issue-190/link2-native-release.json" swift test -c release --no-parallel --filter EnginePlutoMeasurementTests
PLUTO_REFERENCE_OUTPUT="$PWD/.context/issue-190/link2-references-release.json" PLUTO_DIFFERENTIAL_OUTPUT="$PWD/.context/issue-190/link2-differential-release.json" PLUTO_BOUNDARY_OUTPUT="$PWD/.context/issue-190/link2-boundaries-release.json" swift test -c release --skip-build --no-parallel
```

The opt-in measurement test uses a fresh process and measures first use at TT −766,524.75, then 2,000 outer states evenly spanning −766,500 to +766,500 and 2,000 central states from −30,000 in 30-day increments. The baseline is the reviewed link-1 revision plus the same probe logic. Its outer workload includes cold legacy segment generation and repeated beyond-table integration; this is not a steady-state comparison of one cached segment. Both measurements include native time/frame transformations and report peak process RSS. Baseline and candidate checksums differ because the ephemerides differ.

On the measured arm64 macOS host, the release outer workload took 0.06036 s versus 24.23649 s for the legacy model. The central workload took 0.03539 s versus 0.03534 s. First use took 10.59 ms versus 122.05 ms. Peak RSS after both workloads was 104.61 MB versus 100.86 MB; immediately after the cold call it was 62.82 MB versus 47.40 MB. These workloads include different initialization and cache costs, as described above.

The generated Swift files total 9,271,218 bytes. Their compiled C-string sections total 9,270,456 bytes, and their release objects total 18,562,960 bytes before linking. The linked release test executable grew from 139,089,760 to 148,564,224 bytes, including the new tests. The 6,898,944 decoded bytes are additional resident buffers after first outer use.

[The measurement artifact](de441-native-evidence.json) records the host, exact tested source hashes, baseline revision, payload/source/object/executable sizes, timings, peak memory, direct-source residuals, all seam maxima, and archived-reference residuals. Generated source, object file, linked test executable, decoded bytes, and process RSS measure different storage stages. They are not an application download-size or device-performance estimate. No size, speed, radial, or velocity ceiling is inferred from these observations.
