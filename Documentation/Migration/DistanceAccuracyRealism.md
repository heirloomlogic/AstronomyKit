# Practical distance targets for retained models

The initial universal 1 ppm recommendation was premature for the current compact models. After initially approving it, the owner requested advice on realistic expectations rather than blocking on an unrealistic requirement, then explicitly approved the body-specific revision below. The numerical policy and retrospective assessment now reflect that revision; this is an owner-selected engineering requirement, not a qualified pass.

## Recommendation

For a project prioritizing positions and event times while retaining the current compact models, the owner approved body-specific distance requirements: 1 ppm for Sun/Earth/Mercury/Venus/Mars/Jupiter/Saturn, 10 ppm for Uranus/Neptune, and 100 ppm for Moon/Pluto. These round fractional reporting targets provide practical headroom over the sampled current-model disagreements. They are evidence-informed engineering expectations, not independent scientific error bounds, a newly held-out proof, or promises of continuous accuracy through 2130.

| Bodies | Maximum nominal error in the existing samples | Approved target |
| --- | ---: | ---: |
| Sun, Earth, Mercury, Venus, Mars, Jupiter, Saturn | Below 0.60 ppm | 1 ppm |
| Uranus / Neptune | 3.33 / 2.30 ppm | 10 ppm |
| Moon / Pluto | 39.59 / 34.93 ppm | 100 ppm |

The [retrospective assessment](ApprovedDistanceRetrospective.md) contains the complete 5,035-sample original populations and their limitations. Changing a product target must not relabel those already observed values as newly independent acceptance data or change the frozen historical regression allowances.

## Future diagnostic

Before measuring new model residuals, a separate local plan selected eight TT epochs: January 1 of 2101, 2105, 2110, 2115, 2120, 2125 and 2130, plus the final second of 2130. New Horizons file-API responses compare instantaneous geometric lunar radius and heliocentric radius of the other nine bodies. The original source/query metadata checks verify target centers, ICRF, explicit TT, AU/day, NONE corrections, complete epoch coverage, and range/vector consistency; the unchanged production C probe supplies model values.

The 80 new diagnostic samples found maxima of 29.27 ppm for Moon, 2.93 ppm for Uranus, 0.51 ppm for Neptune and 19.62 ppm for Pluto. The remaining six geometric heliocentric series were below 0.41 ppm. These samples support the proposal's practical plausibility at selected future dates, but they do not establish received-light geocentric, angular or event-time accuracy, source uncertainty, all orbital phases, or continuous domain coverage. The Sun was not separately queried in this geometric-radius pilot; its existing Earth-relative evidence remains separate.

Local scripts, predetermined plans, full responses, hash-bound query recipes, production input bindings and measured reports are retained under `.context/distance-realism/`. Run `python3 .context/distance-realism/pilot.py` and `python3 .context/distance-realism/remaining-pilot.py` from this workspace to recompile and replay the cached diagnostic queries without refreshing them. The files are local exploratory evidence, not committed shipping assets or a production acceptance archive.

## Stricter alternative

One ppm is not an inherently impossible ephemeris target. It is plausible as reference-model agreement with different numerical models, subject to actual qualification and source uncertainty. [Primary-source candidate research](AccuracyModelCandidates.md) identifies selected modern DE coefficients/body-center corrections and improved lunar models as possible routes; no route has been qualified over 1900–2130 or measured for package/runtime cost. Full short DE kernels are approximately 31 MiB before outer-body center corrections, while selected/extracted or newly approximated resources could have different costs. Public kernel availability, historical lunar fit residuals and agreement with the same source used to generate coefficients do not independently prove physical astronomical accuracy.

Given the owner's primary position/event use and request to avoid unrealistic blocking, the recommendation is to evaluate the body-specific current-model reporting targets before committing to model replacement solely for a universal 1 ppm requirement. Preserve the accepted one-arcminute angular and strict `<60 seconds` event-time targets as separate requirements; relaxed radial requirements do not prove those targets are met. A failed event/position qualification still requires its own diagnosis and disposition.
