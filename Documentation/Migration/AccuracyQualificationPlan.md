# Accuracy qualification plan

This plan implements the [approved accuracy decisions](AccuracyAcceptanceDecisions.md) without reopening equivalent date-range or event-timing choices. Targets are requirements to investigate; no new whole-domain accuracy pass is claimed. The historical source fixtures, their frozen limits and known failures remain unchanged.

## Fixed requirements

- Date interval: all of calendar years 1900–2130 in explicit TT, ending immediately before 2131-01-01 TT.
- Angular position: at most one arcminute for the Sun, Moon and planets, including Uranus, Neptune and Pluto.
- Reported distance: at most 1 ppm relative error for Sun/Earth/Mercury/Venus/Mars/Jupiter/Saturn, 10 ppm for Uranus/Neptune, and 100 ppm for Moon/Pluto against consistently matched reference distances. Preserve the old empirical regression budgets separately.
- Event time: strictly less than 60 seconds for each comparable event, with correct event existence, identity and direction. Apply the same target to the remaining event families without asking again.
- Priority: positions and event times first; useful reported distances remain a secondary requirement.
- Solar model disposition: retain current production; preserve #124's existing known failure and 70.8-second archive allowance.

## Qualification work

[`fresh-distance-sampling-plan.json`](fresh-distance-sampling-plan.json) binds the revised approved targets and fixes 131 characterization epochs plus 128 fresh holdout epochs over the required interval for all 19 existing distance series. Characterization includes the opening endpoint, final second of 2130 and J2000. The fresh holdout excludes all previously observed distance/future-pilot epochs and the new characterization dates. Its 2,432 planned holdout comparisons have not been acquired or evaluated; this is a distance sampling plan, not a complete angular/event/boundary plan or a qualified acceptance result.

1. Freeze a separate acceptance plan containing the approved interval/targets, API-to-reference observable mapping, source/correction/frame/time conventions, source uncertainty and rounding treatment, endpoint rules, predetermined sampling seeds and difficult geometry/boundary coverage. Keep characterization and held-out acceptance distinct; retain all failures rather than altering limits after measuring them.
2. Archive independent positions for the complete required interval. Existing finite distance/rate archives stop at 2100 and do not establish coverage of 2101–2130. Check the source's actual returned ephemeris and domain, preserve full raw responses/query recipes/hashes, and align the existing center-of-body and geometric/received-light contracts explicitly.
3. Acquire or derive independent event roots from the selected source under each event's explicit definition, at common TT. Rounded minute tables alone cannot settle every strict `<60 seconds` boundary: account for reference precision or use higher-resolution independent roots. Retain event-count, identity and direction controls, including stations, polar crossings and grazing eclipse/transit geometry.
4. Evaluate public production behavior against the frozen plan with injected unit/frame/time/observer/correction/event-selection faults. Root-search precision and internal derivative agreement remain implementation checks rather than astronomical accuracy evidence. Report unsupported source/correction/domain cases and failures explicitly.
5. Compare candidate model repairs only where independent evidence shows a requirement is unmet. Preserve the original evidence, bind any candidate source/model/data snapshot, measure footprint/runtime/build/licensing tradeoffs, use a newly independent holdout, and obtain numerical/code review before claiming qualification. Do not select a replacement just to erase a frozen fixture failure.

## Current finite pilot evidence

[PositionEventValidationEvidence.md](PositionEventValidationEvidence.md) records the independently acquired first batch: 7,511 public position comparisons and 233 matched lunar/heliocentric events over predetermined required-interval samples. There were no nominal angular exceedances; lunar apsis and Pluto-alignment timing exceedances are preserved, alongside two numerical-envelope boundary cases. Geometric/uncorrected distance diagnostics met the revised body-specific targets, while default corrected vector norms require separate treatment. A retrospective DE440 lunar candidate and standalone Swift representation probe establish feasibility only: a 6.28 MiB folded payload agrees with the original evaluator at 42,521 checked states. No production model was changed or whole-domain qualification completed.

## Boundaries and outstanding requirements

Future TT event accuracy is distinct from conversion to future civil UTC and Earth-rotation-dependent local circumstances. Atmospheric and terrain uncertainty is distinct from an idealized apparent-horizon calculation. Preserve these boundaries explicitly; do not turn a deterministic reference comparison into an observed-sunrise or future-clock guarantee.

The new general event-time requirement does not close #124: its archived source-compatible criterion remains independently unmet, even though the separate matched-horizon JPL diagnostic favors the current model. It also does not clear #83's performance gates or change behavior-preserving migration contracts.

The owner replaced the initial uniform 1 ppm distance requirement with the body-specific limits above after reviewing [current-model realism](DistanceAccuracyRealism.md). [The current retrospective assessment](ApprovedDistanceRetrospective.md) finds no nominal exceedances of those revised limits among 5,035 old samples and preserves the old owner-selected 2× regression budgets. These samples predate selection of the product limits and are not a new independent acceptance set. Direct-rate requirements outside their event-time use remain unassigned; they do not prevent the approved position/event/distance qualification work. The local 80-sample future radius pilot is exploratory evidence only. The first frozen position/event batch has now been acquired, evaluated through public APIs and independently reviewed; its finite results and retained failures are linked above. The separate fresh-distance plan remains unacquired, additional event families and continuous behavior remain unqualified, and hosted CI has not been run for this local work.

The owner subsequently selected bundled ephemeris data prototyping. [LunarBundledPrototypeEvidence.md](LunarBundledPrototypeEvidence.md) records native Swift plus pinned ERFA C TT/frame/event integration, the unchanged 6.28 MiB folded payload, and a newly frozen 128-position/52-event lunar holdout with zero sampled exceedances. Integrated local evaluation costs are about 4.9 microseconds per state and 12 MiB total peak process RSS. These finite observations support further lunar integration work; they do not select a production replacement, satisfy #83's performance gates, repair Pluto or complete broader family/domain qualification.
