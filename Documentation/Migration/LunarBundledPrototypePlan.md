# Bundled lunar candidate follow-up

> **Execution:** Continue inline under the owner's independent-work authorization; use a fresh-context implementation review at the end.

**Goal:** Complete the selected bundled-data prototype direction with native TT/frame/event evaluation, fresh premeasurement lunar reference cases and representative local evaluation cost evidence.

**Architecture:** Preserve the shipping package, public models, historical runners and all frozen reports. Reuse the proven folded geometric Moon-center-minus-Earth-center payload in a separate native executable. Compile a development-only, source-pinned ERFA time/date-plane subset alongside Swift; this is an integration probe, not a selected shipping dependency. Freeze a new disjoint 128-position/12-window holdout before acquiring references, enumerate candidate events from full windows independently of reference roots, and compare identities/counts/timing under existing limits.

**Tech stack:** Optimized Swift, source-pinned ERFA 2.0.1 C, local Python reference tools, raw Horizons explicit-TT geometric Moon-center vectors, ignored kernel/payload/build storage.

**Spec:** [AccuracyAcceptanceDecisions.md](AccuracyAcceptanceDecisions.md), [approved-accuracy-targets.json](approved-accuracy-targets.json), and the owner-selected bundled-ephemeris prototype direction.

## Constraints

- Required interval, 1-arcminute position, strict <60-second timing, 100-ppm Moon radius and the fixed 1-second reference numerical allowance remain unchanged.
- TT inputs use the same approximate geocentric ERFA TDB conversion as the prior candidate. Native outputs retain ICRF position and TDB-day derivatives; date-plane/node scalars use ERFA IAU2006 mean-date ecliptic at TT. This does not claim civil UTC or observational covariance.
- Candidate events must be independently enumerated across each complete fresh window, with kinds/order/count checked; do not seed candidate roots from reference roots.
- Separate deterministic source-bound numerical replay from nonrepeatable local cost observations. Name TT/frame work included in timings and exclude public API integration, mixed workloads, Linux/device/concurrency and shipping/licensing gates.
- Keep Pluto body-center repair and all other event families separate. No production model selection or issue closure follows automatically.

## Task 1: Native TT/frame/event integration probe

**Files:** Create `Scripts/reference-data/build-integrated-lunar-probe.py`, `Tools/Migration/LunarIntegratedProbe/main.swift`, `Scripts/reference-data/test_integrated_lunar_probe.py`, `test_integrated_lunar_build.py`, and `integrated-lunar-erfa-source-lock.json`. Generate the pinned ERFA source/build manifest and reusable coefficient evaluator extraction under `.context/accuracy-qualification/integrated-lunar/`; preserve the original native probe source/report.

- [x] Write missing-executable, geocentric TT/TDB/date-plane, independent event enumeration and invalid-window/request controls; observe RED.
- [x] Compile the exact ERFA 2.0.1 source closure pinned to commit `9915ba38c9365f8b0738269b8c2ac1fdd5f8dee3`, with retained notices and per-file hashes. Import its declarations into the standalone Swift executable.
- [x] Implement explicit-TT states, full-window hourly directed apsis/node enumeration and bounded bisection, with request echoes and strict invalid-input rejection; run controls GREEN.

## Task 2: Frozen fresh candidate holdout and evidence

**Files:** Create `lunar-candidate-holdout-plan.json`, `Scripts/reference-data/qualify-lunar-candidate-holdout.py`, `test_lunar_candidate_holdout.py`, separately bound `sources/lunar-candidate-holdout/` raw responses, and the assessment/evidence docs.

- [x] Freeze 128 new position dates (seed 823001) and 12 stratified disjoint 31-day windows (seed 823002), excluding all prior lunar reference windows and observed candidate/reference epochs; store source/policy/exclusion bindings before acquiring new references.
- [x] Test detached plan/query/native-response identity and exact-60-second failures RED→GREEN, reusing validated source/parser/root comparators rather than copying them.
- [x] Acquire geometric Moon/Earth states at all planned positions and complete hourly window grids, then direct-query fixed fine offsets for independently discovered apsides/nodes. Reject incomplete coverage or interpolation ambiguity; preserve raw pairs.
- [x] Evaluate native independent event counts/kinds/order/times and all angle/radius rows; retain every nominal/envelope outcome. Record five local 100,000-state TT/frame trials with load and total peak process RSS; do not apply an unapproved performance threshold.
- [x] Obtain an independent review, fix material findings with regressions, replay source-bound results, run appropriate tests and document remaining production/public API, resource/licensing and qualification gates.
