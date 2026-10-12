# DE-backed planet source foundation

This foundation stores the source components required to replace the selected-window VSOP87B trajectories in issue 248. It does not route a public position, distance, gravity or event calculation through them. Runtime integration and the complete-cycle planetary apsis acceptance remain in the second link.

The chosen interval is the existing 1900–2131 full-weight window plus its 32-day exterior blends. The generator retains every binary64 coefficient from the official type-2 ICRF SPK records that intersect that interval. It checks each source's HTTP identity, DAF layout, target, center, frame, record midpoint and radius, contiguous coverage and retrieved byte-range SHA-256 before replacing generated output.

Mercury, Venus, the Earth-Moon barycenter, Mars, Jupiter and Neptune use DE441 barycenters. Earth adds the DE441 target 399 relative to target 3. Jupiter adds JUP365 target 599 relative to target 5. Neptune adds NEP098 target 899 relative to target 8. The [issue 248 owner decision](https://github.com/heirloomlogic/AstronomyKit/issues/248#issuecomment-6122473231) authorizes Uranus alone to use the DE442 target 7 barycenter embedded in URA184, combined with the DE441 Sun and URA184 target 799 relative to target 7. Saturn continues to use its existing DE441 and SAT441 tables in this link, so its public results are unchanged. The next link will convert Saturn's current Float32 center offset to binary64 while running the public qualification.

The eleven new payloads contain 48,673,224 source bytes and occupy 65,058,541 bytes of generated Swift. The shared 1,393,392-byte DE441 Sun payload already used by Saturn is checked and included in direct fixtures without being stored twice. Each generated literal is private and exposed through a non-inlined accessor. The evaluator decodes only the selected record from the compiled static string and does not widen or retain a complete component table. A truncated record, invalid base64 byte or nonfinite coefficient returns no state.

This follows the record-addressable compiled-literal convention used by the full DE441 Moon. That Moon currently occupies 304,660,529 source bytes and recorded a 132.12-second initial Release build with 8.71 GB peak child-process RSS. On the current host, an isolated Release build of the initial record-addressable representation reported 241.32 seconds and 6,657,769,472 bytes maximum RSS; dependency setup and the focused test run brought wall time to 268.84 seconds. Incremental Release verification at reviewed revision `b03633e39ae9f36b4da8216e307f788a6a6913c7` reported 260.54 seconds, 8,234,041,344 bytes maximum RSS and 278.03 seconds including the focused test. The repaired tree's focused Release build reported 183.23 seconds. Its Release static library is 458,944,160 bytes and test executable is 480,642,592 bytes. An isolated repaired-tree 10,000-state Release sample across all planets measured 2.31 milliseconds for the cold first Jupiter physical-center state and 16.20 microseconds per mixed warm state. `de441-foundation-measurements.json` records the host, toolchain and exact observations. These measurements compare representations and expose costs; they are not acceptance limits or public-route latency.

Issue 245 proposes mapped SwiftPM resources, which would avoid compiling base64 and decoding resident buffers. It remains open because the current engine contract says model data is compiled in and authorizing runtime resource loading requires an owner decision. This link does not make that policy choice. Its per-record decoder also avoids the whole-table allocation that issue 245 measured in the older packed-table design.

`de441-foundation.json` records source identities, retrieved ranges, component layouts and payload digests. `de441-direct-fixtures.json` retains the first, middle and last record at both endpoints and midpoint for each component. Those checks prove source recurrence, storage and clock composition. They are not independent physical accuracy bounds. The unchanged Horizons tolerances and source-selected dense complete-cycle Jupiter, Uranus and Neptune crossing censuses remain required in the integration link.

Run these commands from the repository root:

```sh
python3 -m unittest Scripts/test_generate_planet_de441.py -v
python3 Scripts/generate-planet-de441.py --check
python3 Scripts/generate-planet-de441.py --verify-source
swift test --filter EnginePlanetDE441Tests
PLANET_DE441_MEASUREMENT_PATH=.context/issue-248/release-measurement.json swift test -c release --scratch-path .context/issue-248/release-build --filter EnginePlanetDE441Tests
```

`--check` is offline and verifies the committed inventory, generator bindings, payload shapes and hashes, and fixture inventory. `--verify-source` reads the pinned official ranges and requires the regenerated manifest and direct fixtures to match exactly. Publication writes each generated source and evidence file through an adjacent temporary file and atomic replacement, then replaces the manifest last as the commit marker. An interruption can leave files from two generations, but the retained manifest binds the generated payloads and direct fixture, so `--check` rejects that mixed set. The generator reads no file under `Sources/CLibAstronomy`.
