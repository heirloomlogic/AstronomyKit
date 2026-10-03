# Polar sunrise diagnostic

Issue [#124](https://github.com/heirloomlogic/AstronomyKit/issues/124) records one archived USNO-derived row outside the pinned Astronomy Engine harness allowance: source line 2923, South Pole sunrise on 2022-09-20 at 21:52 UT. The public API at source revision `2ef43fe79a24d92090ce272ef69790228d3cedf9` differs from that minute timestamp by +75.985958 seconds after both values are converted from UT with `Astronomy_DeltaT_EspenakMeeus`. The unchanged allowance is 70.8 seconds.

[`polar-sunrise-diagnosis.json`](polar-sunrise-diagnosis.json) is the raw signed report. `Scripts/reference-data/diagnose-polar-sunrise.py --check` verifies the archived inputs by SHA-256, creates temporary source trees, compiles each control, and compares the checked-in report. The production source is also bound to Git blob `34771ff93a1d07ab09ea5e00f5b5b9bf81087507` from revision `2ef43fe79a24d92090ce272ef69790228d3cedf9`. The pinned source and header come from Astronomy Engine revision `865d3da7d8112bbc7911238052c6af4aaf877181`. No diagnostic switch is compiled into the library.

## Attribution

| Control at source line 2923 | TT error from archived minute | Change from applicable baseline |
| --- | ---: | ---: |
| Pinned source | +70.648379 s | baseline |
| Current source | +75.985958 s | baseline |
| Current source, polynomial disabled | +75.985957 s | −0.000001 s after report rounding |
| Current evaluator, polynomial disabled, pinned VSOP tables | +69.244896 s | −6.741061 s from current full VSOP |
| Current source, pinned nutation value | +77.389442 s | +1.403484 s from current nutation |
| Current evaluator, polynomial disabled, pinned VSOP tables and pinned nutation | +70.648379 s | matches the pinned event time to report precision |

The isolated model controls account for the 5.337579-second event-time difference between the pinned and current sources. The polynomial approximation changes this event by less than one microsecond. The combined pinned VSOP and nutation control reproduces the pinned event time, so the difference does not come from the rise/set search order, root tolerance, or UT-to-TT conversion.

This attribution does not rank either coefficient set or nutation implementation for scientific accuracy. The archived record is minute-resolution source data, and the existing 70.8-second harness allowance remains unchanged. Choosing a production model or replacing the source acceptance rule requires independent accuracy evidence that uses the same apparent-horizon observable.

## Search and time controls

The current event's signed altitude residual at the archived minute is −0.000341795171 degrees. The local signed slope is +0.000004498279 degrees per second, so a small angular model change is amplified at this slow polar crossing. At the returned event, the altitude residual is +0.000000010702 degrees. Repeating the root solve with 10, 1, 0.1, and 0.01-second thresholds changes the returned event by less than 0.003 seconds in every case.

The archived calendar value is a UT coordinate. At that value, Espenak-Meeus Delta T is 73.102832 seconds. Comparing the calculated TT directly with the archive's numeric UT coordinate would produce +149.088789 seconds, while converting both from UT produces +75.985958 seconds. This confirms the fixture's existing `terrestrialTimeDerivedFromUT` convention.

The report also measures the neighboring South Pole sunset and both North Pole crossings from the same table. Their current signed TT residuals are −29.214403, +13.730209, and −25.375327 seconds. Their local slopes are between 0.000004498 and 0.000004575 degrees per second, and their returned-root residuals stay below 0.000000011 degrees.

## Result

No production implementation fault was established. All 5,909 archived rows and the 70.8-second allowance remain intact, including the exact known-issue assertion for source line 2923. Issue #124 stays open for an accuracy-compatible decision about the source/model relationship; issue #81 remains open for its broader model-selection acceptance.
