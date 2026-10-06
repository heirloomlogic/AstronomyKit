# Reference data

Published truth data for the shipping test suite: archived JPL Horizons responses, USNO and NASA catalog tables, and the generator that turns them into offline test fixtures. Tests never contact a network service.

## Fixture provenance

| Fixture under `Tests/AstronomyKitTests/Fixtures` | Read by | Built from |
| --- | --- | --- |
| `IndependentReferences/reference-fixtures.json` | `AuditValidationTests`, decoded by `IndependentReferenceArchive` in `IndependentReferenceFixtures.swift` | `build-fixtures.py`, reading the Astronomy Engine catalog tables (`seasons.txt`, `moonphases.txt`, `moon_nodes.txt`, `moon_apsides.txt`, `earth_apsides.txt`, `riseset.txt`, `local_solar_eclipse.txt`, the NASA eclipse and transit `*.html` pages, `readme-lunar-eclipse.txt`, `normalize-eclipses.py`, `parse-moon-phases.js`) and the Horizons observer and vector responses in `sources/horizons` |
| `IndependentReferences/distance-fixtures.json` | `DistanceAccuracyTests` | Frozen; computed once from the Horizons vectors in `sources/distance/heldout`, with the allowances described below. |
| `SeasonalRoots/seasonal-roots.txt` | `SeasonsTests` | Frozen; computed once from the quarter-longitude crossings of the geocentric Sun vectors (LT+S) in `sources/seasonal-roots/nominal-*`. |

The catalog tables are Astronomy Engine's transformations of USNO season, moon-phase and rise/set output, Fred Espenak's AstroPixels node table, NASA GSFC eclipse and transit catalogs, and the EclipseWise local solar eclipse table, pinned to revision `865d3da7d8112bbc7911238052c6af4aaf877181`. `sources/astronomy-engine-license.txt` is the license for those copied files. Each Horizons response sits beside a `.query.json` recipe holding every API parameter and the response's SHA-256.

The lunar phase (90 s), lunar eclipse (2 min) and rise/set (1.18 min) tolerances are constants in `build-fixtures.py`, taken from Astronomy Engine's C test harness (`generate/ctest.c`) at the same revision.

Each `allowedErrorKm` in `distance-fixtures.json` is 2 × max(characterization maximum, literature floor) + 0.001 km + alignment allowance, rounded up to a multiple of 0.001 km. The characterization maximum is the largest range error AstronomyKit showed for that body and mode against a separate set of Horizons vectors on epochs disjoint from `sources/distance/heldout`. The literature floor is the published ephemeris accuracy scale for the body in km (Mercury 0.347, Venus 2.705, Earth 3.740, Mars 22.794, Jupiter 272.404, Saturn 1000.554, Uranus 229.999, Neptune 1891.819; the Sun uses Earth's, the Moon and Pluto use 0), plus Earth's 3.740 for geocentric series other than the Sun and Moon. The alignment allowance is 1 km for geocentric series other than the Moon and 0 otherwise.

## Regenerate and check

```sh
python3 Scripts/reference-data/build-fixtures.py --check     # verify source hashes and that reference-fixtures.json is current
python3 Scripts/reference-data/build-fixtures.py             # rewrite reference-fixtures.json offline
python3 Scripts/reference-data/build-fixtures.py --refresh   # download the pinned sources and fresh Horizons responses, then rewrite
python3 -m unittest Scripts/reference-data/test_build_fixtures.py -v
```

`--refresh` validates every download before writing any of them.
