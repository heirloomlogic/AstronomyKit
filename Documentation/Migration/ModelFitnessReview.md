# Independent model diagnosis review

Final verdict: approve the completed diagnosis as sampled scientific evidence. No unresolved material review findings remain. Product fitness, replacement selection, production repair, continuous error bounds, and release acceptance are outside this verdict.

Reviewed both diagnostic drivers, the Pluto C probe, archived references/recipes/plans/reports, the 23 diagnostic tests, `OuterPlanetModelDiagnosis.md`, `PlutoModelDiagnosis.md`, the aggregate `ModelFitnessDiagnosis.md`, and the added workflow/inventory integration. The review inspected the VSOP87 source conventions, [Bretagnon and Francou (1988), equation (1)](https://articles.adsabs.harvard.edu/pdf/1988A%26A...202..309B), official TOP2013 Fortran time/frame declarations and rotation, and [NAIF's conditional J2000/ICRF interpretation](https://naif.jpl.nasa.gov/pub/naif/toolkit_docs/C/req/frames.html#ICRF%20vs%20J2000).

## Resolved findings

- P2: DE200 extraction originally described SPICE's identity `DE-200` to `J2000` transform as physical ICRF alignment. The author corrected the recipe, numerical field labels, and explanatory caveats. Native DE200 vector comparisons now use the published VSOP-to-DE200 relation; scalar radial attribution is unaffected.
- P2: The outer-planet offline checker originally compared input hashes and numerical rows but ignored summaries and explanatory metadata, and a nonfinite saved value could bypass its numeric difference check. The author added recursive full-report comparison, finite checks, and adversarial summary/caveat/NaN tests.
- P2: The original Pluto epochs all lie on multiples of 73 days, so the finer replays only tested integration nodes and the coarse off-grid samples were near seed boundaries. The author retained that evidence and added separately frozen near-node and phase-varied interior plans. The final phase grid exercises substantial coarse-cell phases and differing fine-cell phases.
- P2: The developing Pluto parser accepted insufficiently specified reference conventions and truncated states, and derived nonfinite values could bypass residual arithmetic comparisons. The author added exact target/center/solution/frame/time/unit/signature/epoch checks, exact six-component state validation, recursive report finite checks, and adversarial tests.
- Documentation: Initial outer-planet evidence links resolved above the repository root. The coordinator corrected them, and the reviewer verified every local Markdown link in all three new reports resolves.

The final reports correctly describe cached-versus-direct blending as an operational path difference that includes the shortened final integration step. They do not label it a uniquely isolated interpolation truncation bound. The four- versus eight-planet attribution compares matched 4.5625-day steps; the finer replay is not described as a proven error floor.

## Independent verification completed

- `python3 Scripts/reference-data/outer-planet-diagnostic.py check` passed and recomputed the complete report. Log: `.context/model-fitness/outer-review-check.log`.
- `python3 -m unittest discover -s Scripts/reference-data -p 'test_outer_planet_diagnostic.py' -v` passed all 13 tests after final epoch and metric-tolerance hardening.
- `python3 Scripts/reference-data/pluto-model-diagnostic.py --check` passed. `python3 -m unittest discover -s Scripts/reference-data -p 'test_pluto_model_diagnostic.py' -v` passed all 10 tests. The Pluto check verifies archive integrity, reconstructed variant sources, reference contracts, and residual arithmetic; it does not itself compile trajectories.
- An independent compiled replay of original production at 146 days covered all 25 epochs and all four output paths: 100 position-vector comparisons, maximum difference from the archive 0 km on this compiler/platform. Generated source SHA-256: `dd2094db93155731d90a98ac849a74147f3c6a693a2ada6b4b425171ce8b1382`.
- An independent compiled replay with modern seeds and relative eight-planet forces at a 73-day step evaluated non-seed TT day 14600. Cached, forward, backward, and direct-blend vectors each matched the archived force report exactly. Generated source SHA-256: `d013ebe9cacf14dd6607dc61011f0576bf21ba3488aaad6ecaace17b31b3cd5f`. Both independent replays used unique temporary directories and did not alter the author's experiment artifacts.
- Independently recomputed the two bodies' worst-epoch signed radial terms from the archived report and matched the diagnosis tables. The terms telescope per epoch; independently maximized rows and vector norms are not presented as additive causes.
- Independently checked the Pluto matched-step force and phase-grid table values against archived reports. Four-giant radial maximum is 83,664.737 km at 4.5625 days; eight-planet radial/vector maxima are 310.710/371.425 km at that step and 262.363/334.504 km at 2.28125 days. Original 146-day phase-grid cached-versus-direct differences are 9.355406 km radial and 48.185806 km vector.
- The seven protected SHA-256 values in `.context/model-fitness/baseline.json` matched, including production C, the original characterization, allowances, acceptance report, fixture, original probe, and measurement script.
- The added workflow commands are offline and compatible with the existing macOS foundation job. Mapping the new diagnostic test ownership to migration issue #81 preserves the existing inventory contract; separate investigation tracking remains #119. No hosted CI result is implied.

## Pre-commit integrity follow-up

A fresh independent review found that the Pluto manifest omitted the transitive `generated/polynomial-data.h` input. The fix adds that header to the exact source inventory and adds a copied-workspace mutation test: it failed before the fix and now rejects a changed header. The final Pluto archive check and all 24 diagnostic tests pass, including 11 Pluto tests; the reviewer independently reran the 11 Pluto tests and approved the final changes. All trajectory reports, reference responses, and seven protected baseline hashes remain unchanged.

The official TOP2013 evaluator and control downloads now remain beside the coefficient download in `.context/pluto-model`. Committed recipes retain all three source URLs and hashes; optional replay checks cached bytes before compilation. This avoids redistributing source/control downloads without an established grant. Standard-library offline checks still need no TOP2013 download, Fortran compiler, or ERFA installation.

The complete local Swift suite passed 703 tests in 186 suites. All 41 reference-data unit tests and the 20 migration-foundation tests passed. The unchanged distance check passed 2,546 held-out comparisons, and the regenerated migration inventory verifies the additional mutation-test declaration. An alternate GCC 15 probe exactly reproduced 38 held-out rows spanning all 19 body/observable pairs on this local host; this representative compiler check does not establish Linux or hosted macOS results. Current toolchain differences from the historical oracle record remain explicit; local foundation rebuilds agreed with each other.

## Final reviewed artifact hashes

- `Scripts/reference-data/outer-planet-diagnostic.py`: `c4b16bc93a1a30e21b0fd6ae65051622643c4461ad9c989dbf7fc482197f0ecd`.
- `Scripts/reference-data/pluto-model-diagnostic.py`: `e1ed47ad358c41d02048b5839489f1007f6d48d0416abf035a42c4312838000b`.
- `Scripts/reference-data/pluto-diagnostic-probe.c`: `b575f1d136a88f04f342c68082d87d69b9d0653b41f41d9bb05bf312e8688cd2`.
- `sources/distance/model-diagnostics/outer-planets/report.json`: `fbfc3d2ea7a22b3ca5026025ee90ed0e9da1c3c7147419e9851b64d85abc1da1`.
- `sources/distance/model-diagnostics/pluto/manifest.json`: `83519b562c431518f4b459d6d9e2c53d0ca187481b45cd9ffef62458e61a1bbe`.

## Evidence boundaries

The approved outer-planet result is a finite sampled scalar decomposition. The report explicitly leaves physical DE200-to-ICRF vector alignment, consistently anchored satellite-center offsets, individual historical fit changes, continuous bounds, and product error limits unresolved. Pluto's force and seed interventions interact and remain separate comparisons rather than an additive causal budget. Its remaining force/frame/GM/numerical assumptions and extrapolation outside the original characterization window are disclosed. The final aggregate preserves those distinctions. This review independently replayed representative compiled cases, not every expensive fine-step trajectory.
