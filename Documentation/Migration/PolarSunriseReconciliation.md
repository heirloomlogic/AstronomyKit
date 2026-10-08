# South Pole sunrise remains outside the USNO allowance

Issue [#124](https://github.com/heirloomlogic/AstronomyKit/issues/124) covers one failure among 5,909 archived rise/set rows: the Sun rising at the South Pole on 2022-09-20 at 21:52 Universal Time. The public C search at AstronomyKit revision `e3d3d85c804aacf1c13be8249f4350e5013da48e` is +75.985957542 seconds from that minute after the fixture converts both values to TT with Espenak-Meeus. The archived allowance is 70.8 seconds.

`Tests/AstronomyKitTests/Engine/Events/PolarSunriseReconciliationTests.swift` retains the reconstruction. It runs the public search and three native controls, checks the archived row and allowance, repeats the native root search at four tolerances, and compares the finest result with independent bisection. It does not change a production path.

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
| Native, current distance-dependent upper limb | +75.961503026 s |
| Native topocentric, USNO fixed 50-arcminute center depression | -220.637220290 s |
| Native geocentric direction, USNO fixed 50-arcminute center depression | -759.641944652 s |

The native current-definition roots at 10, 0.1, and 0.01-second tolerances are +75.963882124 seconds; the 0.001-second root is +75.961503026 seconds. Their 0.002379-second spread is below the coarsest requested precision, and the 40-step bisection result matches the finest root at the displayed precision. Root convergence does not account for the allowance failure.

## PR #211 did not retain the earlier diagnostic

The newest #124 comment reports a bounded diagnostic at `861b142bf40d14a8735f50d6f8f0919ded81a39b` and refers to PR [#211](https://github.com/heirloomlogic/AstronomyKit/pull/211). That commit changes only `Sources/AstronomyKit/Engine/Stars/EngineConstellations.swift` and `Tests/AstronomyKitTests/Engine/Stars/EngineConstellationTests.swift`. The merged PR contains constellation source, tests, fixtures, and provenance files, but no polar sunrise test, report, or raw diagnostic. The comment's measurements were transient evidence from the #92 investigation.

The current native result is about 0.022 seconds earlier than the transient value reported for `861b142b`. No diagnostic from that revision was retained, and the intervening commits do not change the native Sun position, orientation, horizontal, time, search, rise/set, or vendored C implementations used here. The available evidence therefore does not identify the cause of the difference. The public C result is unchanged. This report binds the retained measurements to `e3d3d85c804aacf1c13be8249f4350e5013da48e` and the test above.

## No correction is justified yet

The current native observable nearly reproduces the public failure, while the published fixed-center alternatives miss the archived minute in the other direction by more than three minutes. These finite controls do not identify the unpublished calculation behind the archived USNO table and do not establish that one model is scientifically more accurate.

A correction needs source evidence for the archived table's actual apparent-horizon calculation or an independent reference that evaluates the same observable. Until then, row 2,923, the 70.8-second allowance, and the known-issue assertion in `AuditValidationTests.swift` remain unchanged. Issue #124 stays open. Issue #92 may continue separate native migration work, but this evidence does not satisfy #124 or support closing it.

## Reproduction

Run `swift test --filter PolarSunriseReconciliationTests` for the retained controls, `swift test --filter AuditValidationTests.riseSet` for all 5,909 archived rows, and `python3 Scripts/reference-data/build-fixtures.py --check` for the pinned source archive. The measurements above used Apple Swift 6.4 on arm64 macOS in Debug; Release is checked separately by the PR validation.
