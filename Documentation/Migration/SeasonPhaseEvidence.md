# Finite season and lunar-phase evidence

This comparison applies the approved strict `<60 seconds` rule to 1,842 events from the pinned USNO-derived archive. It retains 804 seasonal events for every year from 1900 through 2100 and 1,038 lunar quarters from the archive's 21 decennial years over the same range. The machine-readable [sampling plan](season-phase-sampling-plan.json) fixed those rows, identities, hashes, time treatment, target, and omissions before the candidate was measured.

The season comparison has 750 nominal passes and 54 nominal failures. Absolute nominal error reaches 109.725255 seconds. The lunar-phase comparison has 872 nominal passes and 166 nominal failures, with a maximum absolute nominal error of 82.241035 seconds. All 804 season events and all 1,038 lunar events preserve count, identity, and order. [The assessment](season-phase-assessment.json) retains every reference/candidate pair, signed residual, strict comparison result, source line, yearly summary, failure, input hash, runner build receipt, and executable hash.

| Family | Retained events | Nominal `<60 s` | Nominal failures | Maximum absolute nominal error |
| --- | ---: | ---: | ---: | ---: |
| Seasons | 804 | 750 | 54 | 109.725255 s |
| Lunar phases | 1,038 | 872 | 166 | 82.241035 s |

## Reference and time conventions

The source files entered the repository in PR #111 and remain byte-identical to Astronomy Engine revision `865d3da7d8112bbc7911238052c6af4aaf877181`. That project generated the tables from the USNO `/api/seasons?year=YEAR` and `/api/moon/phases/year?year=YEAR` services. The plan pins the table paths and SHA-256 values, the upstream revision and URLs, and both API query templates. The lunar transformation script is also retained. The upstream archive does not contain the individual raw USNO responses, so response-bound query replay is unavailable; this is a provenance limit of the existing source.

The pinned harness treats the serialized calendar fields as UT coordinates and derives TT with its Espenak-Meeus Delta T model. The new runner uses the same treatment for the source coordinates and public searches, then compares TT epochs. This preserves the source convention without changing the historical fixtures or their 142.2-second seasonal and 90-second lunar allowances.

USNO timestamps in these archived tables have one-minute display resolution, and the upstream archive does not record whether they were rounded or truncated. Every nominal residual is still evaluated with strict `<60 seconds`; exactly 60 seconds fails. The missing rounding direction means neither nominal passes nor nominal failures establish the physical event's sub-minute error independently. The report records that precision limit instead of treating minute-formatted rows as exact continuous certification.

## Coverage limits

The season table ends at 2100, so this comparison omits every season from 2101 through 2130. The lunar table contains one calendar year per decade and ends at 2100, so it omits every non-decennial year from 1900 through 2100 and all years from 2101 through 2130. These exclusions follow the archived source availability and the predeclared selection rule; candidate residuals did not choose them.

The comparison measures every retained event but does not prove event completeness or accuracy outside those rows. It also does not supply second-resolution references, source-model uncertainty, future UTC conversion accuracy, or a continuous bound between events. Issue #81 remains open for those gaps and the other unfinished families.

## Offline replay

The isolated runner calls `Seasons.forYear` and `Moon.quarters` through the public Swift API. The Python coordinator validates the approved-policy hash, source hashes, exact row counts, chronological and identity sequences, build manifest, executable, and every generated result. Its mutation tests reject detached policy/source bytes, count/identity/order changes, nonfinite epochs, wrong event selection, time shifts, and the strict 60-second boundary.

```sh
python3 Scripts/reference-data/build-bundled-runner.py
python3 Scripts/reference-data/qualify-season-phase-events.py check
python3 -B -m unittest Scripts/reference-data/test_season_phase_events.py -v
```
