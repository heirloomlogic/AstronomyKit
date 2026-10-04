# Outer-planet and Pluto model-fitness diagnosis

This diagnosis records the pre-bundle production model. The archived failures remain intact; [bundled integration evidence](BundledEphemerisIntegration.md) records the authorized Moon/Pluto repair and its remaining limits.

This investigation follows [DistanceModelFollowup.md](DistanceModelFollowup.md) and is tracked in [issue #119](https://github.com/heirloomlogic/AstronomyKit/issues/119). The owner requested completion of the diagnosis while leaving product limits undecided. Production numerical models, the original distance characterization, allowances, holdout, and acceptance fixtures remain unchanged. New experiment dates were selected before acquiring their reference values; these are diagnostic samples rather than a new acceptance set.

The scientific investigations and their source-bound results are recorded in [OuterPlanetModelDiagnosis.md](OuterPlanetModelDiagnosis.md) and [PlutoModelDiagnosis.md](PlutoModelDiagnosis.md). Raw responses, request recipes, extracted reference states, experiment plans, evaluator provenance, and reports live under `Scripts/reference-data/sources/distance/model-diagnostics/`. Large downloaded kernels, the official TOP2013 evaluator/control/coefficient downloads, and disposable compiled model variants live under `.context/` and are not committed package data; their exact source URLs and hashes remain archived.

## Findings

The independent raw VSOP87B sum agrees with the local radius within five millimetres at the 18 predetermined dates per body and agrees with a 60-decimal-digit calculation within a millimetre. The authors' published check values also reproduce within their printed precision. Arithmetic, coefficient generation, and the production polynomial approximation are therefore not material explanations at these dates.

| Maximum absolute radial difference over the 18 diagnostic dates | Uranus (km) | Neptune (km) |
| --- | ---: | ---: |
| Raw full VSOP87B minus DE200 | 537.802 | 3,643.865 |
| DE200 minus DE441 | 8,687.502 | 8,516.241 |
| Raw full VSOP87B minus DE441 | 8,454.394 | 8,959.687 |

At each body's largest raw-minus-DE441 radial residual, the DE200-to-DE441 difference supplies most of the signed residual. Neptune also retains a substantial raw-to-DE200 contribution. This identifies scientific-reference evolution as material without assigning its difference to particular observations or physical terms. Historical AU and TT/TDB sensitivities are measured and too small to explain these residuals at the selected dates. Physical DE200-to-ICRF vector alignment and isolated satellite-center offsets remain unresolved and are not hidden inside the radial conclusion.

The official TOP2013 evaluator reproduces the five selected stored Pluto seed states within 0.1 metre when replaying the historical numeric epoch convention. Their exact-seed radial differences from the modern system-barycenter reference reach about 216,077 km, so reducing the integration step alone cannot remove that mismatch. The 25-date diagnostic covers four complete seed intervals, including bracketing seeds outside the original 1900–2100 characterization window.

Controlled replays distinguish additional dynamics and numerical effects. With modern seeds and heliocentric relative equations, the four-giant force model retains an approximately 83,665 km sampled radial maximum at a 4.5625-day step. Adding the terrestrial planets reduces the sampled radial/vector maxima to approximately 311/371 km at that step and 262/335 km at 2.28125 days. These are coupled experimental results, not an accepted replacement, a continuous bound, or a pure causal partition. The report retains the prescribed-Sun comparison, convergence ladder, remaining model/frame/constants limitations, and separate evaluation between cached nodes.

Separate interior samples probe substantial fractions of the 146-day cache step and varied phases of the finer steps. On that phase grid, the original 146-day cached path differs from directly blended propagation by up to 9.355 km radially and 48.186 km in vector norm; the finest experimental eight-planet replay gives 0.000719/0.002608 km. This compares operational evaluation paths: cached interpolation and the direct replay's shortened final integration step both contribute. It is not a uniquely isolated interpolation-error bound, and the earlier near-node experiment is retained separately.

## How to interpret the evidence

Implementation agreement, fit to a historical ephemeris, agreement with a modern reference, product usefulness, and release acceptance are distinct checks. An angular requirement cannot set a radial kilometre limit. The existing owner-selected 2× empirical allowance remains a finite regression policy; its observed maxima do not become product requirements.

For outer planets, signed radial differences telescope along the raw VSOP87B → DE200 → DE441 chain. Individual maxima can occur at different dates and cannot be added as a worst-case attribution. Vector norms do not telescope as scalar causal contributions. DE200's dynamical frame, the production FK5 transform, and modern ICRF require explicit treatment, even though radius is rotation invariant. Center and barycenter Horizons requests may also use different planetary, satellite, and Sun solutions; their returned trajectory differences do not isolate physical satellite-center displacement.

For Pluto, exact-seed comparisons isolate stored-state/reference mismatch from propagation away from a seed. Changing only the step size tests numerical convergence in the held-fixed model. Modern-seed substitution, relative gravity equations, and added terrestrial perturbers are separate controlled experiments with interacting effects. Their differences must not be presented as an additive causal error budget. The experiment reports also distinguish direct forward/backward propagation, blending, and cached interpolation.

TOP2013 is fitted to INPOP10a over 1890–2000, uses TDB, and models the Pluto-Charon barycenter. Its published fit residuals do not establish an error bound against modern DE441 or for AstronomyKit's custom integrator. Diagnostic samples outside the fit interval must remain explicit extrapolation evidence. See the [official TOP2013 README](https://ftp.imcce.fr/pub/ephem/planets/top2013/README.pdf) and [IMCCE theory descriptions](https://www.imcce.fr/recherche/equipes/pegase/theories).

## Repair and replacement choices

| Option | What it addresses | What remains to establish |
| --- | --- | --- |
| Retain the current models with an explicit distance-accuracy disposition | Preserves the behavior used by the C-to-Swift migration oracle. | Product observables, centers, useful errors, and date range; a clear disposition for unmet requirements. |
| Repair Pluto seeds, forces, integration, or blending | Targets causes isolated by the controlled replays while retaining a compact state representation. | A coherent frame/time/center/force contract, new characterization and holdout, derivatives, seams, cache/concurrency behavior, and runtime cost. |
| Evaluate TOP2013 or a compact approximation derived from a selected model | Offers an analytical or compact representation with explicit provenance. | Applicable redistribution rights, modern-reference fitness on the chosen interval, approximation/derivative evidence, and measured storage/build/runtime costs. |
| Evaluate selected modern DE coefficients or kernels | Changes the fitted scientific reference and provides explicit system-barycenter states. | Body-center corrections, supported interval, coefficient extraction/evaluator validation, notices, independent holdout, and measured package/runtime costs. |

The [NAIF planetary kernel catalog](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/) contains DE440, DE441, and DE442. DE442's [technical comments](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de442_tech-comments.txt) describe a Uranus-focused update; that is a future sensitivity experiment, not a reason to relabel the frozen DE441 diagnosis. Short kernels are roughly 31 MB and long DE441 distribution parts roughly 1.5 GB each; those server sizes are not measured Swift binary costs. The API's broader accepted domain and a selected product domain may require different coverage choices.

The [NAIF use rules](https://naif.jpl.nasa.gov/naif/rules.html) permit unmodified kernel redistribution and impose attribution/metadata requirements on modified kernels. The inspected TOP2013 distribution did not establish an explicit shipping license. Public availability and scientific diagnostic access do not settle production redistribution rights.

## Offline reproduction

Use CPython 3.14.7 for the frozen offline evidence commands below; `python3` must resolve to that runtime. The macOS workflow installs it explicitly. Python 3.9 computes slightly different floating-point norms and can change byte-exact distance replay and a rounding-only diagnostic summary, even when every frozen distance allowance still passes. This runtime requirement preserves the historical reports and source hashes; it does not claim portable bit identity or alter an astronomical acceptance budget.

Run these source-bound diagnostic checks and evidence-contract tests from the workspace root. They use archived reference bytes; acquisition and expensive exploratory replays are separate explicit commands described in the individual reports.

```sh
python3 Scripts/reference-data/outer-planet-diagnostic.py check
python3 Scripts/reference-data/pluto-model-diagnostic.py --check
python3 -m unittest discover -s Scripts/reference-data -p 'test_*diagnostic.py' -v
python3 Scripts/reference-data/distance-accuracy.py check
python3 -m unittest Scripts/reference-data/test_distance_accuracy.py -v
swift test --filter DistanceAccuracyTests
Scripts/migration/generate-contract-inventory.py --check
```

The macOS workflow includes both new offline diagnostics and their evidence tests. The migration inventory assigns the new independent-evidence tests to #81; the separate model-fitness investigation and decisions are tracked in #119. These workflow edits do not establish hosted CI results. Original production, characterization, allowance, acceptance, fixture, and original measurement-script hashes are checked against the pre-investigation workspace snapshot; successful existing distance tests do not establish a new model's fitness.

## Validation and independent review

Local macOS validation on 2026-10-02 passed both new offline diagnostic checks, all 23 new diagnostic tests, all 20 migration-foundation tests, and the unchanged original distance check with 2,546 held-out comparisons. The original distance evidence's eight Python tests and Swift distance suite also passed; the Swift suite contains two tests, including 2,546 parameterized distance cases. The migration inventory was regenerated and verified against the final test sources. All seven protected baseline hashes remained unchanged.

A fresh independent reviewer approved the diagnosis after the authors corrected material findings about DE200 frame semantics, full-report/nonfinite validation, Pluto reference contracts, and interpolation sampling. [ModelFitnessReview.md](ModelFitnessReview.md) preserves the findings, reviewed artifact hashes, checks, and limits. The reviewer separately compiled all 25 original Pluto epochs at a 146-day step and a non-seed modern-seed eight-planet case at a 73-day step; every compared vector matched its archive exactly on this machine. That representative replay does not independently reproduce every expensive fine-step trajectory or establish portable bit identity.

Pre-commit integrity review also bound the transitive polynomial coefficient header, added a mutation regression, and kept official TOP2013 downloads in the local replay cache. The final local full Swift suite passed 703 tests in 186 suites; 41 reference-data tests, including 24 diagnostic tests, and 20 migration-foundation tests passed. Both diagnostic checks, the unchanged 2,546-comparison distance check, seven protected baseline hashes, and the regenerated inventory passed. The follow-up receipt and final reviewed artifact hashes are in [ModelFitnessReview.md](ModelFitnessReview.md).

The approval concerns sampled diagnosis and evidence integrity. Product acceptance, a replacement choice, continuous error bounds, hosted CI, downstream integration, and release readiness remain outside it.

## Next decision

The subsequent [owner decision record](AccuracyAcceptanceDecisions.md) sets 1900–2130 TT, inclusive, as the distance/model-fitness accuracy target. Existing finite distance acceptance covers only 1900–2100. Numerical product limits and replacement selection remain open; the approved date target does not expand the historical evidence's validated coverage.

The diagnosis supports specific repair experiments and identifies reference/model differences that arithmetic changes cannot remove. Model selection remains open by the owner's instruction. Before selecting a production change, define maximum useful radial and 3D vector errors independently of these measurements, intended geometric or received-light observables, center semantics, and the required date range. Then compare candidate fitness and cost, freeze a new model and acceptance policy, and acquire a newly independent holdout. Retain the historical evidence and keep finite sampled claims separate from continuous accuracy guarantees.

Issue #119 remains open for those model-fitness decisions and acceptance gates. The behavior-preserving port contracts in #85 and #88 remain distinct; neither completed diagnosis nor an improved experimental replay establishes completion of #81, downstream validation, hosted CI, or release readiness.
