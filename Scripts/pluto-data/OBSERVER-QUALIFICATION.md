# Native Pluto observer qualification

Forty-one archived Horizons observation epochs test the native geocentric consumer beyond the direct state samples in the [integration evidence](de441-native-method.md). All three direction comparisons use the owner's 1′ target. The existing 1.5′ allowances for older fixtures do not apply here. The per-epoch measurements and source bindings are in [observer-evidence.json](observer-evidence.json).

Per-configuration residuals and maxima are recorded in the source-bound artifact. These are sampled results. They do not establish continuous full-range physical-center accuracy, velocity accuracy, or event timing. The public facade now uses the qualified engine, and the separate public heliocentric gates cover the archived center, blend, and outer epochs. The [complete PLU060 qualification](PLU060-QUALIFICATION.md) records the physical-center expansion; #92 owns production searches.

## Sources and time scales

The epoch list was frozen before retrieval. Fourteen outer epochs span TT −1461000 to +1461000 days from J2000, including both exact engine endpoints, their one-day interior neighbors, and ten further interior samples. They use Pluto system barycenter 9 from DE441 because a physical-center ephemeris is unavailable over the full range. The twelve original center-999 epochs remain archived. Fifteen new dates cover both expanded 32-TDB-day transitions, their interior neighbors, and the Horizons endpoint, for twenty-seven center rows. Recorded emission TDB ranges from −73046.739955 to +73045.297056 days, inside the verified PLU060 interval [−73047.5, +73046.5). Center queries report `plu060_merged`; all queries report Earth 399 from DE441. Neither response supplies a full-range bound on the missing outer center correction.

[observer-fixtures.json](observer-fixtures.json) records the exact query parameters, URLs, response SHA-256 values, and parsed directions. The unchanged publisher responses are in `observer-sources/`. The capture tool reuses `reference-data/build-fixtures.py` for requests and envelope validation; offline checks reject changed target/source, observer, frame, epoch, row count, nonfinite values, or archive digest.

Horizons receives and returns explicit JD TT, with `TLIST_TYPE=JD`; no ancient calendar or UT conversion is inferred. Its [API documentation](https://ssd-api.jpl.nasa.gov/doc/horizons.html) defines these switches. The native test constructs time by inverting `.jplHorizons` Delta T from the same TT. The shared apparent solver holds reception fixed and solves elapsed TDB light time with TT parameters. The numerical residual check compares elapsed TDB with range/c at its unchanged 1e-9-day limit; this is a numerical check, not a physical timing allowance.

## Compared quantities

Horizons quantities 1, 45, and 2 are respectively astrometric ICRF, airless apparent ICRF, and airless apparent true-equator/equinox-of-date directions. Quantity 21 supplies down-leg light time in minutes as a diagnostic, with no new distance or timing tolerance. These definitions are documented in the [Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html).

The test calls `CelestialBody.pluto.geocentricPosition` with `.none` and `.corrected`, converts the public vectors to the engine's EQJ representation for comparison, rotates the apparent result to EQD, and compares directions with stable cross/dot angular separation. ICRF references receive the existing frame bias before comparison with EQJ. Native light time now uses a common barycentric origin, finite-source solar deflection and relativistic observer aberration. Shapiro delay and planetary deflection remain omitted. Native and Horizons precession/nutation conventions also differ. The larger EQD residual includes those frame differences; it is not attributed solely to the Pluto representation.

Omitting Earth subtraction misses 1′ at all 41 epochs; omitting the frame conversion misses at 40. These controls show that the composed tests detect those omissions. They do not prove sensitivity to every small correction. The artifact also records aberration displacement and light time without turning either observed maximum into policy.

## Domain and remaining work

The direct heliocentric state accepts the engine TT ±1461000-day range. Geocentric positions accept both endpoints for both aberration modes, including a 0.025-day grid through the first 0.3 days after the lower endpoint. Nonfinite and out-of-range observations reject. The light-time-only evaluator first validates the observation, preserves its Delta T model, requires finite internal scales no later than the observation, and permits earlier Pluto states only where the compiled Pluto and Sun tables overlap. Their joint TDB coverage is [−1461016.5, +1461015.5), derived from the generated table metadata rather than a fixed padding assumption.

The endpoint tests cover `backdatedPosition`, position and state composition, ecliptic state and rate, equatorial and horizontal coordinates, and Sun-dependent angles. The common apparent composition keeps Earth at reception and admits two TT days of private emission padding subject to actual source coverage; public Earth and other direct body queries remain range-checked. The endpoint Horizons directions gate the composition at the same 1′ limit. The earlier Pluto-only light-time helpers retain their own internal guard tests but are no longer the public apparent route. These composition checks do not independently qualify full-range velocity accuracy or event timing.

Solar angle, pair longitude with the Sun, and elongation accept both exact engine endpoints under the common source padding. Adjacent exterior and nonfinite reception times still throw. This changes the previous model's lower-endpoint rejection as part of #256's public apparent-place integration; it does not expand the public TT range or establish endpoint validity for searches whose windows extend outside it.

## Offline reproduction

```sh
python3 -m unittest Scripts/test_capture_pluto_observers.py -v
python3 Scripts/capture-pluto-observers.py --check
PLUTO_OBSERVER_OUTPUT=/tmp/pluto-debug.json swift test --no-parallel --filter EnginePlutoConsumerQualificationTests
PLUTO_OBSERVER_OUTPUT=/tmp/pluto-release.json swift test --no-parallel -c release --filter EnginePlutoConsumerQualificationTests
python3 Scripts/capture-pluto-observers.py --record-native /tmp/pluto-debug.json /tmp/pluto-release.json
python3 Scripts/capture-pluto-observers.py --check
```

The record command binds outputs to the current native engine and test/capture sources. `--check` checks the archived measurements and bindings; it does not execute Swift. Rerun the two Swift commands to independently reproduce residuals. `--capture` explicitly fetches new publisher responses and replaces the fixtures; it is not part of offline verification and may require a new reviewed baseline if Horizons changes.

Validation results for this implementation are recorded in the pull request. The reproduction commands above remain the authoritative way to refresh the source-bound artifact after engine or qualification-test changes.
