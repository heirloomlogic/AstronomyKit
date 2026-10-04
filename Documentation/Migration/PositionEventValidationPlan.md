# Position and event validation implementation plan

> **For agentic workers:** Execute this plan inline using `superpowers:executing-plans`; the owner explicitly authorized independent execution. Preserve the existing workspace and its unrelated evidence. Progress and command output live in `.context/accuracy-qualification/`.

**Goal:** Measure the current public Swift implementation against independent position vectors and lunar apsis roots over the approved 1900–2130 TT interval, retaining every failure and uncovered family.

**Architecture:** Freeze [position-event-sampling-plan.json](position-event-sampling-plan.json) before acquisition, archive Horizons responses with query and plan hashes, and evaluate a streaming Swift runner that calls public APIs. Keep sampled numerical results, correction mismatches, and physical accuracy claims separate.

**Tech stack:** CPython, NASA/JPL Horizons file API, Swift Package Manager, public AstronomyKit APIs, offline unittest replay.

**Spec:** [AccuracyAcceptanceDecisions.md](AccuracyAcceptanceDecisions.md) and [approved-accuracy-targets.json](approved-accuracy-targets.json).

## Global constraints

- Position error is at most 1 arcminute; event error is strictly less than 60 seconds, with matching count, identity, and direction.
- The target interval is 1900-01-01 TT inclusive through 2131-01-01 TT exclusive; reference interpolation may evaluate endpoint guards, but counted samples/events remain in the target interval.
- Positions and event timing have priority; revised body-specific distance limits are secondary and remain unchanged.
- Retain the current solar model and #124's archived failure/allowance; do not change production models or historical fixtures to eliminate new residuals.
- A finite sample does not certify continuous accuracy. ICRF versus the implementation's J2000/FK5 frame, body-center approximations, fixed-heliocentric light time, default aberration approximation, and source physical uncertainty remain explicit.

## Review focus

- A swapped center, time scale, correction mode, body ID, date population, or detached query must fail reference validation.
- Angular comparisons must survive tiny angles and reject nonfinite/zero vectors, and a wrong axis/sign must exceed the fixed limit.
- Event interpolation must reject multiple/no crossings, retain ascending/descending range-rate direction, and compare root order/count with public results rather than matching only the nearest convenient event.
- Exactly 60 seconds fails. A numerical envelope that crosses the threshold must be classified inconclusive rather than silently passed.
- Whole-period and unsupported event-family gaps remain visible even if all acquired rows pass.

## Task 1: Frozen independent reference archive and comparison mathematics

**Files:** Create `Scripts/reference-data/qualify-position-events.py`, `Scripts/reference-data/test_position_events.py`, and `Scripts/reference-data/sources/position-events/`; read the frozen sampling plan and owner policy.

**Interfaces:** The acquisition tool consumes explicit body/center/correction recipes and produces response-bound JSON pairs; `angle_arcminutes(a, b)`, `interpolated_root(rows, degree)`, and `event_classification(error_seconds, numerical_allowance)` provide offline comparison primitives.

- [x] Write and run tests for angular unit/sign faults, zero/nonfinite vectors, strict event boundaries, scalar root direction/uniqueness, and query/response metadata corruption. Expected: the new comparison functions are missing before implementation.
- [x] Implement the primitives and archive commands without modifying the historical distance/polar tools. Run `python3 -m unittest discover -s Scripts/reference-data -p 'test_position_events.py' -v`. Expected: all new controls pass.
- [x] Acquire the 29 fixed position series at 131 characterization and 128 holdout epochs, and the 16 predetermined 31-day lunar event windows. Refine each independently discovered range-rate root with the fixed fine offsets. Expected: complete response-bound coverage or an explicit acquisition error, never a skipped series/window.

## Task 2: Public Swift evaluation and reproducible evidence

**Files:** Create `Tools/Migration/AccuracyQualificationRunner/main.swift` and `Scripts/reference-data/build-accuracy-runner.py` for an isolated scratch package; create `Documentation/Migration/position-event-assessment.json` and `PositionEventValidationEvidence.md`.

**Interfaces:** The batch runner reads JSON lines with `operation`, `body`, `mode`, and TT epochs/windows; returns public position vectors or ordered lunar apsides with kinds, TT times, and distances. It preserves the existing migration runner and root package manifest, both bound by the historical comparison archive.

- [x] Build with `python3 Scripts/reference-data/build-accuracy-runner.py`; run a batch containing a Moon vector and a lunar window. Expected: a finite vector and alternating, ordered public events.
- [x] Evaluate every frozen position row and independently enumerated event against the public API. Record nominal angular/time thresholds, revised distance thresholds as secondary diagnostics, interpolation convergence, missing/extra events, and source conventions. Expected: a complete report whose failures are preserved.
- [x] Run the offline replay command, all reference-data Python tests, and the appropriate Swift tests. Expected: deterministic report reproduction and green harness tests; astronomical exceedances remain evidence and do not become harness errors or widened limits.
- [x] Obtain a fresh review of the acquisition/parser/root/comparator/public-runner changes and address material findings; report remaining source uncertainty, domain sampling limits, uncovered families, and any new model decision required by demonstrated failures.

## Task 3: Independent geometric event extension

**Files:** Create `Scripts/reference-data/qualify-geometric-events.py`, `test_geometric_events.py`, `geometric-event-sampling-plan.json`, and the separately bound `sources/geometric-events/` archive; extend the isolated public batch runner with lunar-node and heliocentric-alignment operations.

**Interfaces:** Reuse the validated raw vector parser, monotonic polynomial root interpolator, request-bound public batch protocol, and strict event comparator. The new reference scalar uses independently pinned ERFA `ecm06` in explicit TT: normalized lunar ecliptic `z` for nodes, and `direction*sin(Earth longitude - planet longitude)` for alignments, with inner direction `-1` and outer direction `+1`. This scalar finds both 0° and 180° events without longitude wrap discontinuities; crossing direction determines their identity. Keep local frame bias/model approximation inside the nominal physical-reference residual, rather than claiming exact coordinate parity.

- [x] Freeze the nine full-year alignment windows (1900, 1930, 1960, 1990, 2020, 2050, 2080, 2101, 2130), eight planet body centers, reused 16 lunar-node windows, fine offsets and numerical controls before evaluating those event residuals.
- [x] Run the independent ERFA matrix, kind-mapping, and unpaired-epoch fault tests. Expected: missing new functions fail before implementation; all controls pass after implementation.
- [x] Acquire all coarse and fine event references, with separate plan-bound recipes. Run `python3 Scripts/reference-data/qualify-geometric-events.py acquire`. Expected: explicit complete coverage of every planned case, including legitimate zero-event windows.
- [x] Evaluate all public event counts, kinds, order, TT times and strict numerical-envelope classifications. Run the `report` and `check` commands. Expected: retain every exceedance and count/direction failure; do not widen targets or substitute a better-fitting center/frame.
- [x] Review the new extension independently and run final Python/Swift checks. The reference dependency is local development tooling, with wheel, installed binary and version provenance; it does not become a shipping package dependency.

## Search-versus-model diagnosis

`diagnose-lunar-event-search.py` independently bisects the norm of public geometric lunar vectors using three fixed explicit-TT central stencils (0.001, 0.0002 and 0.00004 day), for all 35 matched apsides. Its fixed ±10-second directed brackets and 14 iterations test whether event-search tolerance accounts for the independent residual. It is a same-model diagnostic and cannot qualify the lunar model or the independent source. Bind its report to the parent assessment and executable, and retain every stencil result.

## Task 4: Native lunar representation feasibility

**Files:** `native-lunar-probe-plan.json`, `probe-native-lunar-candidate.py`, `test_native_lunar_probe.py`, and the standalone `Tools/Migration/NativeLunarProbe/main.swift`; generated payload/executable remain in ignored scratch storage.

Fold only identical Moon/Earth coefficient grids, frame and type. Preserve the public body-center contract, evaluate geometric ICRF states at split TDB, and compare position components and analytic derivatives against the original full-kernel evaluator with fixed 1e-7 km and km/day limits. Evaluate every retained record midpoint/boundary, excerpt guards and all archived lunar cases. Measure five warm sequential one-million-state trials and separate baseline process peak RSS; do not treat a microbenchmark or peak difference as production, mixed-workload or continuous-accuracy qualification.

- [x] Freeze the development-only parity/cost plan before measurements; run polynomial, derivative, boundary, malformed payload/request and split-date precision controls RED→GREEN without widening limits.
- [x] Review the new representation/evaluator independently, verify deterministic source-bound parity, and record storage/timing/RSS evidence with its remaining native API, holdout and shipping gates.
