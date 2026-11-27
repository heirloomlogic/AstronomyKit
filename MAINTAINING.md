# Maintaining AstronomyKit

This document is for maintainers. It describes AstronomyKit's pure-Swift computation engine (`Sources/AstronomyKit/Engine/`), which ports Don Cross's [Astronomy Engine](https://github.com/cosinekitty/astronomy) (2.1.19, commit `826e26ff3a6dc03ee46658b1138fef582d96c5d9`), how its numerical behavior differs from upstream, and how to refresh the ephemeris tables. Day-to-day contribution guidance lives in [CONTRIBUTING.md](CONTRIBUTING.md).

## Engine structure

All astronomical math and ephemeris tables live in pure Swift under `Sources/AstronomyKit/Engine/`, with no C target or C bridge. The public Swift API sits directly above those internal modules in `Sources/AstronomyKit/`.

## Version & tag scheme

Release tags are AstronomyKit's own [semantic version](https://semver.org), `X.Y.Z`, with no build metadata. Releases before 4.0.0 were tagged `X.Y.Z+upstream-A.B.C`; that suffix was dropped because upstream Astronomy Engine development ended at its final release, 2.1.19.

## Differences from upstream Astronomy Engine 2.1.19

Upstream Astronomy Engine was single-threaded by design and targeted ±1 arcminute accuracy. AstronomyKit advertises `Sendable` safety and tighter event timing, so the Swift engine carries these changes relative to upstream 2.1.19:

1. **Pluto orbit cache lock.** An `NSLock` in `EngineGravityPluto.swift` guards the Pluto segment cache (`PlutoCache`). Segments are immutable once constructed, and `AstronomyConfig.reset()` clears the cache under the same lock.

2. **Stateless fixed stars and lazy constellation frame.** `FixedStar` evaluates J2000 catalog coordinates directly in `EnginePositions.starGeoVector` without mutable star slots. `EngineConstellation` initializes its J2000→B1875 rotation matrix via Swift's thread-safe `static let`.

3. **Pluto compute denial-of-service guard.** `EngineGravityPluto.calcPluto` rejects times more than `plutoMaxCrawlDays` (~100 years) beyond the 51-state table (`±730,000` TT days) with `AstronomyError.badTime` instead of crawling arbitrarily far.

4. **Extreme-input guards.** Non-finite or extreme inputs return errors or finish in constant time without altering ordinary results: rise/set and altitude searches reject non-finite `limitDays` (`invalidParameter`) and non-advancing steps (`badTime`); Pluto rejects non-finite TT (`badTime`); lunar node and Neptune/Pluto apsis searches reject non-advancing steps or non-finite starts (`badTime`); `EngineMath.longitudeOffset` and `normalizeLongitude` reduce with `fmod(x, 360.0) + 0.0` in constant time; and `EngineTime.timeFromTT` returns a NaN time for non-finite TT and bounds iteration to 128 steps (stopping early when iterates alternate across a forward Delta T step while preserving exact `tt`).

5. **Accepted time range.** Ephemeris entry points validate `AstroTime.acceptedTTDays` (`|TT| ≤ 1,461,000` days, 4,000 Julian years either side of J2000) and throw `AstronomyError.badTime` outside it or for non-finite times. Pluto keeps its narrower range (item 3).

6. **Degenerate Lagrange inputs.** `EngineLagrangePoint` throws `invalidBody` when both bodies are identical, throws `invalidParameter` for zero/non-finite separation, degenerate L4/L5 orbital planes, or non-finite output fields, and bounds the L1–L3 Newton loop to 10,000 steps (`noConvergence`).

7. **Observed Delta T (value-carried).** `EngineTime.deltaTObserved` (`DeltaTModel.observed`) is the default model in place of Espenak–Meeus, whose 2005–2050 polynomial has drifted from observed Earth rotation (about 6 seconds high by 2027). Each `AstroTime` carries its `DeltaTModel` by value (and `Seasons.forYear(_:deltaT:)` takes it explicitly), with no process-global mutable selector. The observed model interpolates linearly in a yearly table of IERS values from 1962; before 1962 it joins Espenak–Meeus with an offset that fades linearly to zero by 1952; after the table, the last yearly rate continues and blends smoothly into the long-term parabola by 2150. See "Refreshing the Delta T table" below.

8. **TT-continuous offsets.** `AstroTime.addingTerrestrialDays(_:)` (`EngineTime.addTerrestrialDays`) adds a span to both `ut` and `tt` so light-travel iterations and numerical derivatives never step across a Delta T piecewise boundary.

9. **Longer planet series.** The VSOP87B tables in `EngineVsopTables.swift` hold 1,262 terms across Mercury through Neptune where upstream kept 466. Every upstream term is kept; the added terms come unchanged, in file order, from the published VSOP87B files (`https://ftp.imcce.fr/pub/ephem/planets/vsop87/VSOP87B.mer` through `.nep`). See "Selecting planet series terms" below.

10. **Series cosine.** `EngineVsop.swift` evaluates VSOP87B series two terms at a time using FMA-contracted `SIMD2<Double>` minimax polynomials (`seriesHalfCos`, `seriesHalfSinc`) and branchless `seriesWrap` in Release and non-Apple builds, evaluating coordinates and derivatives in one pass. On Apple platforms in Debug builds, `Package.swift` defines `ASTRONOMYKIT_SERIES_ACCELERATE` and links `Accelerate`, and `EngineVsop` batches each planet's contiguous series through `vDSP_vsmaD`, `vvcos`/`vvsincos`, and `vDSP_dotprD` using a thread-local scratch buffer.

11. **Nutation series.** `EngineNutation.swift` sums all 77 terms of the IAU 2000B nutation series (McCarthy and Luzum, 2003) where upstream kept the five largest. The 77 arguments pair one of 14 multiples of `l` and `l′` with one of 18 multiples of `F`, `D`, and `Ω`: the five fundamental angles are reduced by whole turns with `rint` (keeping extreme finite times finite), evaluated once, and combined by angle addition. Release and non-Apple builds evaluate the sum with FMA-contracted `SIMD2<Double>` sharing `EngineVsop.seriesHalfCos`/`seriesHalfSinc`; Apple Debug builds batch the 77 terms with `vvsincos`, `vDSP_vindexD`, `vDSP_zvmulD`, and `vDSP_dotprD`. `NutationTests` checks the result against the published term-by-term sum and SOFA's reference test value.

## Selecting planet series terms

Nothing is committed but the tables: no VSOP87 files and no scripts. The terms in `EngineVsopTables.swift` were selected this way:

1. The reference events came from the complete VSOP87B series: over 1900–2100, every station of Mercury through Neptune, every time one of them is 17′, 8.5° or 17° from the Sun in longitude, and every sign ingress of the Sun, Mercury, Venus and Mars. Longitudes are geocentric and corrected for light time.
2. Each VSOP87B term was scored by the change in those event times that dropping it alone causes, as a root mean square over the events of one planet and one kind. A term's score is its largest such value. An Earth term was scored against every planet's events and the Sun's.
3. The tables hold every upstream term, and every other term that scored at least the threshold for its body:

   | Body | Threshold | Terms | Upstream |
   |---|---:|---:|---:|
   | Mercury | 1.5 s | 98 | 29 |
   | Venus | 1.5 s | 85 | 26 |
   | Earth | 1.5 s | 162 | 51 |
   | Mars | 2 s | 294 | 91 |
   | Jupiter | 2 s | 157 | 72 |
   | Saturn | 2 s | 216 | 91 |
   | Uranus | 2 s | 180 | 76 |
   | Neptune | 3 s | 70 | 30 |

4. Each kept term is its amplitude, phase and frequency columns exactly as the file prints them, in file order within each series.

The largest frequency in the tables is 316,428 radians per millennium. `seriesWrap` is valid while a frequency times 4 millennia stays below 6.5e6 radians, which holds for frequencies up to 1.6e6.

## Refreshing the Delta T table

Refresh `ObservedTable` in `Sources/AstronomyKit/Engine/EngineTime.swift` before each release, so the table ends about a year past the release date. Nothing is committed but the table: no data files or scripts.

1. Download the IERS EOP 20 C04 series (`https://hpiers.obspm.fr/iers/eop/eopc04/eopc04.1962-now`) and the rapid series with predictions (`https://maia.usno.navy.mil/ser7/finals2000A.all`).
2. For each day, Delta T = 32.184 s + (TAI − UTC) − (UT1 − UTC), taking UT1 − UTC from C04 where it exists and from finals2000A after it. TAI − UTC is 37 s since 2017; earlier values are in the IERS Bulletin C history.
3. For each Julian epoch Y.0 from 1962.0 to the last whole year the predictions reach, interpolate Delta T linearly at UT days since J2000 = 365.25 (Y − 2000), and write it to 3 decimals.
4. Append the new entries, update `observedCount` and the retrieval date comment in `EngineTime.swift`, and update the last year stated in `DeltaTModel.observed` (`AstronomyKit.swift`) and `tableEnd` in `DeltaTObservedTests`.
5. Run `DeltaTObservedTests`, and bump `AstronomyConfig.ephemerisVersion` at release, since results change.

## Verification

Run the full suite — the JPL/Audit accuracy tests are the correctness gate, and ThreadSanitizer guards the concurrent engine state:

```sh
touch .dev-tooling          # enable dev tooling for local builds
swift package resolve
swift build
swift test                  # all suites, incl. JPLValidationTests / AuditValidationTests
swift test --sanitize=thread  # exercises concurrent Pluto cache and multi-model AstroTime calculations
```

The accuracy suites (`JPLValidationTests`, `AuditValidationTests`) assert against JPL Horizons and audit reference positions to roughly ±1 arcminute. `EventTimingTests` holds nine station, solar band and equinox times of 2026–2027 to within 10 seconds of JPL Horizons, and four Jupiter and Saturn stations to within 20; they depend on the longer planet series (item 9) and the full nutation series (item 11). CI runs these jobs plus release-configuration and per-platform builds on every pull request.
