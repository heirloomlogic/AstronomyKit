# Lunar frame preflight

This directory tests whether a fixed DE440 principal-axis (PA) to mean-Earth (ME) frame rotation explains AstronomyKit's lunar-libration latitude offset from NASA Scientific Visualization Studio tables. It does not change the runtime model, fixtures, or acceptance limits.

## Result

The exact `3c31e2d56eb4e887554ea185f5f75bdb78b3a674` AstronomyKit model reproduces the existing 2020–2022 comparison over all 26,305 hourly rows. Its latitude residual has a signed mean of +1.404705 arcminutes and a maximum absolute value of 1.669177 arcminutes. Its longitude maximum is 0.110343 arcminutes. These results remain inside the existing 1.67-arcminute latitude and 0.1304-arcminute longitude gates.

Treating the captured output as PA coordinates and applying NAIF's fixed PA-to-ME rotation reduces the latitude RMS from 1.412287 to 0.175370 arcminutes, an 87.58% reduction. The same rotation raises the longitude maximum to 1.215677 arcminutes, 9.32 times the existing longitude gate. Applying the rotation in the reverse direction raises the latitude maximum to 2.979288 arcminutes.

The rotation therefore has the right scale and direction to account for much of the latitude offset, but a whole-frame PA-to-ME conversion does not explain the two-coordinate SVS comparison. A latitude-only correction would discard the longitude counterexample and is not supported by this result.

NASA SVS names DE421, UTC, a geocentric observer, and the apparent center of the lunar disc. Its pages do not name the lunar body-fixed frame, orientation-kernel version, state/light-time recipe, aberration treatment, or emission-versus-reception epoch. The frame convention behind those tables remains unresolved. This preflight also does not evaluate the DE440 binary PCK orientation or select a runtime blend and transition, so issue #255 remains open.

## Sources and conventions

`source-receipts.json` binds every input to its byte count and SHA-256 digest. The three tables, the Astronomy Engine license, the capture program, and the captured model output also record their exact base path or source revision. Publisher pages and NAIF text kernels record their retrieval URL and time. The replay rejects missing entries, wrong container types, changed bytes, absolute paths, path traversal, and paths outside this directory.

The pinned SVS pages describe hourly geocentric values for 2020, 2021, and 2022. The 2020 table contains 8,785 rows through 2021-01-01 00:00 UT, while the next two contain 8,760 rows each through their final hour; the repeated 2021 boundary is retained because the existing gate checks every published row. Their tables label the source time as UT. The capture passes that calendar coordinate to AstronomyKit as universal time and records the library's corresponding terrestrial time after its Espenak-Meeus Delta T conversion. The NAIF PCK comment states its coverage as 1549-12-31 through 2650-01-25 in ephemeris time/TDB. This fixed-rotation test is epoch-independent and does not equate those clocks.

The NAIF frame kernel defines `MOON_PA_DE440` relative to ICRF/J2000 and `MOON_ME_DE440_ME421` relative to `MOON_PA_DE440`. For column vectors, the replay uses `v_ME = R1(0.2785 arcseconds) R2(78.6944 arcseconds) R3(67.8526 arcseconds) v_PA`, with right-handed positive rotations. Its matrix is checked to 16 decimal places against CSPICE N0067 `pxform("MOON_PA_DE440", "MOON_ME_DE440_ME421", et)` and has determinant one. The inverse control uses the transpose.

The frame kernel says the fixed ME frame is closely aligned with the DE421 mean-Earth frame. That statement does not establish that SVS used this frame or the same observation recipe.

## Files

- `sources/` contains the pinned publisher pages, frame documentation, exact-base SVS tables, and their license.
- `capture.swift` records the exact-base AstronomyKit output. `base-libration.json` is the resulting 26,305-row capture.
- `replay.py` validates provenance, parses every source row, derives the fixed rotation, runs the comparisons and negative controls, and writes `report.json` atomically. It rounds report floats to 12 decimal places after all calculations so supported Python versions produce identical evidence bytes; calculations and gate comparisons use unrounded binary64 values.
- `test_replay.py` tests the source contract, provenance failures, full coverage, clock pairing, matrix convention, existing gates, frame directions, and invalid one-hour/axis-swapped inputs.

## Reproduce

The offline replay requires Python 3 and no network access:

```sh
python3 Scripts/lunar-frame-preflight/replay.py --check
python3 -m unittest Scripts/lunar-frame-preflight/test_replay.py -v
```

The checked-in capture was produced from a clean checkout of the recorded base with Apple Swift 6.4. Its exact commands are stored as an argument array in `source-receipts.json`. Re-running the capture requires that exact source revision and a Debug build made with `-enable-testing`; the offline replay does not require Swift.
