# Native sunrise meets the polar allowance; the public C facade is unchanged

The new native `Engine.Events.searchRiseSet` uses a 696,000 km apparent optical solar limb and passes all 5,909 archived rows. Its South Pole residual is +50.550159736 TT seconds, within the unchanged 70.8-second allowance. The public facade remains on C until [#96](https://github.com/heirloomlogic/AstronomyKit/issues/96), so its known-issue assertion and [#124](https://github.com/heirloomlogic/AstronomyKit/issues/124) remain open.

The retained public failure is the Sun rising at the South Pole on 2022-09-20 at 21:52 Universal Time. The public C search at AstronomyKit revision `e3d3d85c804aacf1c13be8249f4350e5013da48e` is +75.985957542 seconds from that minute after the fixture converts both values to TT with Espenak-Meeus. The archived allowance is 70.8 seconds.

`Tests/AstronomyKitTests/Engine/Events/PolarSunriseReconciliationTests.swift` retains the reconstruction. It runs the public search and three native controls, checks the archived row and allowance, repeats the native root search at four tolerances, and compares the finest result with independent bisection. Those controls retain the old nominal-radius observable; the new native event path is tested separately in `EngineObserverEventsTests` and `EngineObserverSourceTests`.

## Sources and time convention

The source row is line 2,923 of [`Scripts/reference-data/sources/riseset.txt`](../../Scripts/reference-data/sources/riseset.txt), SHA-256 `92f5c1edf647c3f46d8964cfab06315fbe09cb580bc512d1418d41039424ff48` and Git blob `6881977efe8901aa308bb6d172d413016f4b84a8` at the tested revision. It reads `Sun     0 -90 2022-09-20T21:52Z r`.

The archived [USNO page](https://github.com/cosinekitty/astronomy/blob/865d3da7d8112bbc7911238052c6af4aaf877181/generate/riseset/sun_2022_E0_S90.html) is pinned to Astronomy Engine revision `865d3da7d8112bbc7911238052c6af4aaf877181` and has SHA-256 `9809e03c06f235738936b59fa636d06a9a819219a4d5e55ba95b22c0d5d8b7e8`. Its heading names the South Pole, longitude 0 degrees, latitude 90 degrees south, and Universal Time. The September 20 rise entry is 21:52.

The fixture parses `2022-09-20T21:52Z` as a Gregorian calendar coordinate, converts it to days since J2000, and passes that number to `AstroTime(ut:deltaTModel:)` with `.espenakMeeus`. The comparison uses TT after the same conversion for the calculated event. The archived minute is modeled UT1 for this harness. Treating its number as TT or passing it through the civil UTC table is a different convention.

The official [USNO rise/set definition](https://aa.usno.navy.mil/faq/RST_defs) says sunrise is the upper edge of the solar disk on the horizon under average atmospheric conditions. Its computational definition puts the Sun's center 50 arcminutes below the geometric horizon: 16 arcminutes for an average apparent solar radius plus 34 arcminutes for average horizon refraction. USNO also warns that rise/set accuracy decreases at high latitudes because a shallow crossing turns small angular differences into large time differences.

## Observable controls

The public search calls `Astronomy_SearchRiseSetEx`. At sea level its zero is unrefracted topocentric center altitude plus `asin(695700 km / topocentric distance)` plus 34 arcminutes. The first native control evaluates that same distance-dependent upper-limb expression with `Engine.Positions.equatorial`, native observer subtraction, precession and nutation, `Engine.Horizontal`, `Engine.Time`, and `Engine.Search`.

The second native control keeps the topocentric coordinates but replaces the varying solar radius with USNO's published fixed 50-arcminute center depression. The third uses a geocentric solar direction, rotates it into the South Pole horizon, and applies the same fixed center depression. The geocentric case is a control, not a proposed rise/set implementation.

All native searches start at 2022-01-01 00:00 UT, carry Espenak-Meeus through every derived `Engine.Time`, scan at the C search's 0.42-day interval for at most 366 days, and solve the ascending root. The test exercises tolerances of 10, 0.1, 0.01, and 0.001 seconds. Forty bisection steps provide a separate root calculation on the same bracket.

| Control | Signed TT residual from the archived minute |
| --- | ---: |
| Public C rise search | +75.985957542 s |
| Native control, 695,700 km distance-dependent upper limb | +75.961503026 s |
| Native topocentric, USNO fixed 50-arcminute center depression | -220.637220290 s |
| Native geocentric direction, USNO fixed 50-arcminute center depression | -759.641944652 s |

The native nominal-radius control roots at 10, 0.1, and 0.01-second tolerances are +75.963882124 seconds; the 0.001-second root is +75.961503026 seconds. Their 0.002379-second spread is below the coarsest requested precision, and the 40-step bisection result matches the finest root at the displayed precision. Root convergence does not account for the allowance failure.

## PR #211 did not retain the earlier diagnostic

The newest #124 comment reports a bounded diagnostic at `861b142bf40d14a8735f50d6f8f0919ded81a39b` and refers to PR [#211](https://github.com/heirloomlogic/AstronomyKit/pull/211). That commit changes only `Sources/AstronomyKit/Engine/Stars/EngineConstellations.swift` and `Tests/AstronomyKitTests/Engine/Stars/EngineConstellationTests.swift`. The merged PR contains constellation source, tests, fixtures, and provenance files, but no polar sunrise test, report, or raw diagnostic. The comment's measurements were transient evidence from the #92 investigation.

The current native result is about 0.022 seconds earlier than the transient value reported for `861b142b`. No diagnostic from that revision was retained, and the intervening commits do not change the native Sun position, orientation, horizontal, time, search, rise/set, or vendored C implementations used here. The available evidence therefore does not identify the cause of the difference. The public C result is unchanged. This report binds the retained measurements to `e3d3d85c804aacf1c13be8249f4350e5013da48e` and the test above.

## Independent optical-limb evidence

Four archived [JPL Horizons](https://ssd.jpl.nasa.gov/horizons/manual.html) responses near the polar minute use Sun center 10, Earth center 399, the geodetic South Pole, TT input and no atmospheric refraction. At the reference TT, the native airless center altitude is only 0.000007645458 degrees above Horizons. Linear interpolation of the source altitude plus the existing 695,700 km radius and 34-arcminute refraction gives approximately +77.59094 seconds from the reference TT. Moving the trajectory toward this source would make the old timing residual larger.

A separate [USNO celestial-navigation API](https://aa.usno.navy.mil/data/api) comparison identifies the limb convention. At three dates, its printed apparent semidiameter and a Horizons topocentric distance imply these radii:

| UT date, noon at 0° longitude and latitude | USNO semidiameter | Inferred radius |
| --- | ---: | ---: |
| 2000-01-03 | 0.271100° | 695,999.418 km |
| 2022-07-04 | 0.262196° | 696,001.076 km |
| 2022-09-20 | 0.265429° | 695,998.777 km |

All three agree with 696,000 km within the six-decimal-degree printing resolution and exclude 695,700 km. The pairing uses USNO UT1 and the same numerical UTC coordinate for the Horizons distance; the archived DUT1 and range rate make this subsecond distance mismatch negligible relative to the printed semidiameter resolution. An additional noon-side site at 150°W on September 20 reports 0.265459°, retaining a separate site check. [NASA's 2019 eclipse calculation](https://svs.gsfc.nasa.gov/4711/) explicitly uses a 696,000 km optical radius. [IAU 2015 Resolution B3](https://arxiv.org/abs/1510.07674) defines 695,700 km as a nominal conversion constant; it does not require that number for every apparent-limb event convention.

The native rise/set path therefore retains its distance-dependent angular radius and 34-arcminute refraction, using 696,000 km for the Sun's apparent limb. No other solar-radius consumer changes. This is a source-supported event convention, not a fit to the polar timestamp or a claim about the Sun's physical radius at every wavelength. The three native semidiameters match the printed USNO values within 0.000001 degree; the nominal-radius controls miss that comparison by over a factor of 100. The current USNO one-day service independently reproduces the archived 21:52 entry. Its rise/set implementation is unavailable, and the navigation service's convention does not prove which internal calculation produced that entry.

With the optical radius, the same four Horizons points give an interpolated polar crossing about +52.15501 seconds from the reference TT. The native root is +50.550159736 seconds with the original 0.1-second search tolerance. These are sampled comparisons under specified conventions, not a continuous event-time bound or a prediction of actual atmospheric refraction.

Exact queries, raw responses, digests and derived fixtures are under [`Scripts/observer-event-data`](../../Scripts/observer-event-data/README.md). The complete native Debug/Release captures and source-bound summary preserve every USNO row and the independent observables. The old controls, archived minute, tolerance and public known issue remain intact.

## Reproduction

Run `swift test --filter EngineObserverEventsTests` for the native complete-row acceptance and `swift test --filter EngineObserverSourceTests` for the independent source comparisons. Run `swift test --filter PolarSunriseReconciliationTests` for the retained controls, `swift test --filter AuditValidationTests.riseSet` for all 5,909 archived rows, and `python3 Scripts/reference-data/build-fixtures.py --check` for the pinned source archive. The measurements above used Apple Swift 6.4 on arm64 macOS in Debug; Release is checked separately by the PR validation.
