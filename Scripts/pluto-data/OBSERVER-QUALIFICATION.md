# Native Pluto observer qualification

Twenty fresh Horizons observation epochs test the native geocentric consumer beyond the direct state samples in the [integration evidence](de441-native-method.md). All three direction comparisons use the owner's 1′ target. The existing 1.5′ allowances for older fixtures do not apply here. The per-epoch measurements and source bindings are in [observer-evidence.json](observer-evidence.json).

Debug and release produce identical residuals. Their maxima are 0.001053′ for astrometric ICRF, 0.001004′ for apparent ICRF, and 0.152969′ for apparent equator-of-date directions. These are sampled results. They do not establish continuous full-range physical-center accuracy, velocity accuracy, event timing, or public API behavior. #190 remains open; #96 owns public cutover and #92 owns production searches.

## Sources and time scales

The epoch list was frozen before retrieval. Eight outer epochs span TT −766524 to +766524 days from J2000, with six interior epochs spaced through the range. They use Pluto system barycenter 9 from DE441 because a physical-center ephemeris is unavailable over the full range. Twelve center-999 epochs cover 1840, J2000, 2159, and both 32-day transitions, including quarter-day offsets that place reception and emission on opposite sides of a blend boundary. Center queries report `plu060_merged`; both queries report Earth 399 from DE441. Neither response supplies a full-range bound on the missing outer center correction.

[observer-fixtures.json](observer-fixtures.json) records the exact query parameters, URLs, response SHA-256 values, and parsed directions. The unchanged publisher responses are in `observer-sources/`. The capture tool reuses `reference-data/build-fixtures.py` for requests and envelope validation; offline checks reject changed target/source, observer, frame, epoch, row count, nonfinite values, or archive digest.

Horizons receives and returns explicit JD TT, with `TLIST_TYPE=JD`; no ancient calendar or UT conversion is inferred. Its [API documentation](https://ssd-api.jpl.nasa.gov/doc/horizons.html) defines these switches. The native test constructs time by inverting `.jplHorizons` Delta T from the same TT. The existing light-time solver steps modeled UT and derives TT again; it does not silently reinterpret its step as TDB. Native ephemerides retain their own TT/TDB conversion.

## Compared quantities

Horizons quantities 1, 45, and 2 are respectively astrometric ICRF, airless apparent ICRF, and airless apparent true-equator/equinox-of-date directions. Quantity 21 supplies down-leg light time in minutes as a diagnostic, with no new distance or timing tolerance. These definitions are documented in the [Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html).

The test calls `Engine.Positions.geocentricPosition` with `.none` and `.corrected`, rotates the apparent result to EQD, and compares directions with stable cross/dot angular separation. ICRF references receive the existing frame bias before comparison with EQJ. Native light time uses heliocentric positions and corrected aberration backdates Earth with Pluto as a first-order approximation. Horizons uses barycentric light time, stellar aberration and gravitational deflection. Their precession/nutation conventions also differ. The larger EQD residual includes those frame differences; it is not attributed solely to the Pluto representation.

Omitting Earth subtraction misses 1′ at all 20 epochs; omitting the frame conversion misses at 19. These controls show that the composed tests detect those omissions. They do not prove sensitivity to every small correction. The artifact also records aberration displacement and light time without turning either observed maximum into policy.

## Domain and remaining work

The direct heliocentric state retains its exact TT ±766525-day range. Geocentric positions accept both endpoints for both aberration modes, including a 0.025-day grid through the first 0.3 days after the lower endpoint. Nonfinite and out-of-range observations reject. The light-time-only evaluator first validates the observation, preserves its Delta T model, requires finite internal scales no later than the observation, and permits earlier Pluto states only where the compiled Pluto and Sun tables overlap. Their joint TDB coverage is [−766536.5, +766535.5), derived from the generated table metadata rather than a fixed padding assumption.

The endpoint tests cover `backdatedPosition`, position and state composition, ecliptic state and rate, equatorial and horizontal coordinates, solar angle, pair longitude, and elongation. A pinned internal state guards the source-backed position and velocity calculation. These composition checks do not independently qualify full-range velocity accuracy or event timing. The public API remains C-backed until #96, so this native change does not alter its behavior. #190 remains open for full-range physical-center qualification; #92 and #96 retain their existing scopes.

## Offline reproduction

```sh
python3 -m unittest Scripts/test_capture_pluto_observers.py -v
python3 Scripts/capture-pluto-observers.py --check
PLUTO_OBSERVER_OUTPUT=/tmp/pluto-debug.json swift test --filter EnginePlutoConsumerQualificationTests
PLUTO_OBSERVER_OUTPUT=/tmp/pluto-release.json swift test -c release --filter EnginePlutoConsumerQualificationTests
python3 Scripts/capture-pluto-observers.py --record-native /tmp/pluto-debug.json /tmp/pluto-release.json
python3 Scripts/capture-pluto-observers.py --check
```

The record command binds outputs to the current native engine and test/capture sources. `--check` checks the archived measurements and bindings; it does not execute Swift. Rerun the two Swift commands to independently reproduce residuals. `--capture` explicitly fetches new publisher responses and replaces the fixtures; it is not part of offline verification and may require a new reviewed baseline if Horizons changes.

Validation results for this implementation are recorded in the pull request. The reproduction commands above remain the authoritative way to refresh the source-bound artifact after engine or qualification-test changes.
