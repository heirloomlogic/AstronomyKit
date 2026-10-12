# DE-backed planet trajectories

AstronomyKit uses compiled DE-backed trajectories for Mercury through Neptune from 1900-01-01 through 2131-01-01 TT, with 32-day exterior blends to the retained polynomial/VSOP87B model. Public positions, states and distances use physical planet centers. Gravity and GM-weighted origins use system centers from the same source tables.

The generator retains every binary64 coefficient from the official type-2 ICRF SPK records that intersect the selected interval and blends. It checks each source's HTTP identity, DAF layout, target, center, frame, record midpoint and radius, contiguous coverage and retrieved byte-range SHA-256 before replacing generated output. Mercury, Venus, the Earth-Moon barycenter, Mars, Jupiter and Neptune use DE441 barycenters. Earth adds the DE441 target 399 relative to target 3, Jupiter adds JUP365 target 599 relative to target 5, Neptune adds NEP098 target 899 relative to target 8, and Saturn adds SAT441 target 699 relative to target 6. The [issue 248 owner decision](https://github.com/heirloomlogic/AstronomyKit/issues/248#issuecomment-6122473231) authorizes Uranus alone to use the DE442 target 7 barycenter embedded in URA184, combined with the DE441 Sun and URA184 target 799 relative to target 7.

The eleven generated DE441/DE442 components contain 48,673,224 bytes. Saturn's binary64 barycenter, Sun and center-offset tables contain 19,400,016 bytes, for 68,073,240 payload bytes across the selected trajectories and 91,128,561 bytes of generated Swift source. The shared DE441 Sun is stored once. Each generated literal is private and exposed through a non-inlined accessor; the evaluator decodes only the selected record and does not retain a decoded component table. A truncated record, invalid base64 byte or nonfinite coefficient returns no state.

This representation follows the compiled record-addressable convention used by the full DE441 Moon. A mapped SwiftPM resource could reduce compiler and product costs, but it would change the package's compiled-data convention; [issue 245](https://github.com/heirloomlogic/AstronomyKit/issues/245) owns that decision. The current route downloads and opens no runtime file.

On the recorded macOS arm64 host with Apple Swift 6.4, the final focused Release build reported 173.31 seconds, 186.54 seconds wall time and 8,307,769,344 bytes maximum resident set size. The Release static library is 470,750,624 bytes and the test executable is 492,628,992 bytes. A fresh Release process measured 0.377 milliseconds for the first public Jupiter state and 12.80 microseconds per state over 10,000 mixed public planet evaluations. These are host observations, not portable acceptance ceilings. `de441-foundation-measurements.json` separates the earlier foundation measurements from the routed integration observations.

`de441-foundation.json` records source identities, retrieved ranges, component layouts and payload digests. `de441-direct-fixtures.json` retains the first, middle and last record at both endpoints and midpoint for each component. Those checks prove source recurrence, storage and clock composition; the unchanged Horizons suites provide the public direction and distance checks.

`de441-cycle-census.json` is selected from the direct source rather than native event output. For Jupiter, Uranus and Neptune it covers one nominal orbital cycle, evaluates physical-center and system-center range rate every three hours, repeats at 1.5 hours and requires the same complete crossing inventory. Exact-zero samples and every sign change are retained and refined below 0.01 second. The artifact contains 4 physical and 2 system crossings for Jupiter, 6 and 2 for Uranus, and 430 and 6 for Neptune. Global system-center apocenter and pericenter select the nearest same-kind physical crossings, matching the native Neptune search's global-distance classification. The six native residuals range from -9.958 to +9.615 seconds under the unchanged 60-second requirement.

Run these commands from the repository root:

```sh
python3 -m unittest Scripts/test_generate_planet_de441.py Scripts/test_planet_cycle_census.py Scripts/test_saturn_ephemeris.py -v
python3 Scripts/generate-planet-de441.py --check
python3 Scripts/generate-planet-de441.py --verify-source
python3 Scripts/generate-saturn-tables.py --check
python3 Scripts/generate-planet-cycle-census.py --check
python3 Scripts/record-planetary-event-evidence.py --check
swift test --filter 'EnginePlanetDE441Tests|EnginePlanetPositionsTests|EngineSaturnEphemerisTests|EnginePlanetaryEventTests|EnginePlanetHorizonsTests'
```

The table generators read no file under `Sources/CLibAstronomy`. `generate-planet-de441.py` publishes each generated source and evidence file through an adjacent temporary file and atomic replacement, then replaces the manifest last as the commit marker. `generate-planet-cycle-census.py` also publishes its validated artifact atomically. An interrupted mixed planet-table generation fails the offline manifest check.
