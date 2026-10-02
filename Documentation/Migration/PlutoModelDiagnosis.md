# Pluto seed and integration diagnosis

Investigated 2026-10-02 for [issue #119](https://github.com/HeirloomLogic/AstronomyKit/issues/119). This is a controlled model diagnosis. Product radial/vector limits remain undecided; production source, the existing distance measurement script, characterization, holdout, and acceptance budgets are unchanged. The experiments identify several material causes without choosing a replacement model or asserting an additive error budget.

## Findings

The stored seeds are faithful samples of full TOP2013. The official IMCCE Fortran evaluator reproduces the five tested seed positions within **0.098 metre** and velocities within **1.05 × 10⁻¹³ km/s**, when evaluated with the historical numeric TT-as-TDB convention. The unmodified official program also reproduces all **1,045 numeric fields** of the official control file exactly at its printed precision. This rules out seed transcription and the upstream C translation as explanations at these five samples. It does not make TOP2013 agree with a newer fitted ephemeris.

Seed replacement and smaller steps are insufficient by themselves. Replacing the five seeds with modern Horizons target-9 states and reducing the production integration step from 146 to 18.25 days changes the maximum sampled cached radial residual from **133,555 km to 92,971 km**. With the same modern seeds, a controlled heliocentric equation using direct and indirect forces from the four giant planets still gives **83,665 km** at 4.5625 days. Adding the four inner planets to that same equation gives **311 km** at the same step and **262 km** at 2.28125 days. Omitted terrestrial forces are therefore a material cause in this controlled comparison; prescribing the Sun's approximate barycentric trajectory is a separate material difference. These comparisons interact with seeding, numerical integration, and endpoint blending, so their maxima must not be added as independent contributions.

## Frozen samples and reference contract

The [initial plan](../../Scripts/reference-data/sources/distance/model-diagnostics/pluto/plan.json) was written before acquisition. Its SHA-256 is `174c391f03156b779d87f6e2b9ba7efe6e0f73b32be8408bd3c1d579e4f767a2`. The five exact seed times are TT days `−58400, −29200, 0, 29200, 58400` relative to JD `2451545`. Every one of the four intervals has predetermined offsets `73, 7300, 14600, 21900, 29127` days: 25 unique samples. The support seeds bracket the 1900–2100 domain and extend to 1840–2159; maxima over all 25 samples are explicitly distinct from the subset inside 1900–2100. The initial step ladder is `146, 73, 36.5, 18.25` days.

All modern requests specify geometric heliocentric ICRF state vectors, `TIME_TYPE='TT'`, `CENTER='500@10'`, `OUT_UNITS='AU-D'`, and `VEC_CORR='NONE'`. Target `9` is the Pluto-system barycenter and uses DE441 for target and Sun. Target `999` is Pluto's body center and uses `plu060_merged` for both target and Sun in these responses. The API identifies itself as NASA/JPL Horizons API version 1.2. Both contracts are retained; one is not selected after observing residuals. The [Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html) distinguishes planetary system barycenters and satellite/body-center ephemerides. Their returned trajectory difference is not a pure physical satellite offset because the fitted source solutions also differ.

The [IMCCE description of TOP2013](https://www.imcce.fr/recherche/equipes/pegase/theories) identifies its Pluto trajectory as the Pluto–Charon barycenter. Comparing it with target 9 is much closer to the intended center than target 999, but target 9 includes the complete modeled satellite system. TOP2013 is fitted to INPOP10a, not DE441. Its published fit accuracy cannot be transferred to this integrator or to a different fitted reference. The [official evaluator and coefficients](https://ftp.imcce.fr/pub/ephem/planets/top2013/) use TDB and the dynamical ecliptic/equinox of J2000; the evaluator's own obliquity `23°26′21.41136″` and longitude rotation `−0.05188″` are retained for ICRS output. ERFA `dtdb` at the geocenter converts TT to TDB for the modern comparisons. Numeric TT-as-TDB is evaluated separately only to reproduce historical seed generation.

## Seed and reference-model contribution

The upstream [generator at the exact vendored revision](https://raw.githubusercontent.com/cosinekitty/astronomy/826e26ff3a6dc03ee46658b1138fef582d96c5d9/generate/codegen.c) loads full `TOP2013.dat`, planet 9, and calls `TopPosition` at `i × 29200 − 730000` before printing the seed table. The official coefficient file hash matches the upstream `top2013.sha256`: `cb3950fe79eb2edf5255bfbf5ca28c276f2793a18f6b1de01b01dcb7c8a2017f`. The downloaded source hashes and source URLs are archived in `top2013-sources.json` and `upstream-provenance.json`.

| TT days from J2000 | TOP2013 minus modern barycenter radial residual (km) | Vector residual (km) |
| ---: | ---: | ---: |
| −58400 | +194096.474 | 417991.889 |
| −29200 | +71245.000 | 92713.232 |
| 0 | +9476.152 | 9571.446 |
| +29200 | +107187.129 | 213674.705 |
| +58400 | +216077.375 | 584517.279 |

These exact-seed residuals cannot be attributed to integration away from a seed or cache interpolation. The comparison establishes a TOP2013-versus-modern-reference discrepancy, including the stated center/time/reference distinctions. It does not isolate observational revisions within INPOP/DE, identify the entire discrepancy as a physical satellite offset, or prove the behavior between these dates.

## Integration, prescribed origin, and omitted forces

The C probe includes isolated generated copies of `astronomy.c`; it calls the production integrator and changes only explicitly named diagnostic ingredients. Each variant's exact generated-source hash is archived. The original-seed step variants retain all original seeds. Modern-seed variants substitute only the five measured heliocentric position/velocity states, after which the production `GravFromState` conversion applies the local Sun position and velocity normally. This avoids interpreting heliocentric seeds as barycentric.

The production force path prescribes approximate barycentric positions for the Sun and four giant planets from VSOP. The Sun trajectory is not obtained by integrating the same acceleration law applied to the test particle. A second controlled path instead integrates the exact Newtonian heliocentric test-particle equation for the chosen prescribed perturbators:

```text
r'' = −GM_sun r / |r|³ + Σ GM_i [(r_i − r) / |r_i − r|³ − r_i / |r_i|³]
```

This path uses the same heliocentric VSOP trajectories and GM constants, sets the coordinate origin to the Sun, and includes the indirect acceleration explicitly. Comparing its four-giant version with the original prescribed-origin path changes the coordinate-origin dynamics while retaining the selected perturbators. Comparing its four- and eight-planet versions changes the omitted planetary forces while retaining that equation and coordinate convention. The eight-planet version locates Earth-plus-Moon GM at the VSOP Earth position, an explicitly retained approximation to EMB; it does not add satellite dynamics, relativistic forces, asteroids, or Pluto's own GM to the Sun term.

The [force plan](../../Scripts/reference-data/sources/distance/model-diagnostics/pluto/force-plan.json), [eight-planet convergence extension](../../Scripts/reference-data/sources/distance/model-diagnostics/pluto/convergence-plan.json), and [four-giant convergence extension](../../Scripts/reference-data/sources/distance/model-diagnostics/pluto/omission-plan.json) were each frozen before their replay. The extensions are adaptive diagnostic follow-ups prompted by unconverged residuals, not members of the original sampling plan. No step was selected to pass a product threshold.

| Seed model / force path | Step (days) | Maximum absolute radial residual (km), all 25 epochs | Maximum vector residual (km), all 25 epochs |
| --- | ---: | ---: | ---: |
| Original / production | 146 | 216077.374 | 584517.275 |
| Original / production | 18.25 | 216077.374 | 584517.275 |
| Modern / production | 146 | 133555.224 | 143043.728 |
| Modern / production | 18.25 | 92970.936 | 93748.769 |
| Modern / relative four giants | 18.25 | 83277.302 | 84097.753 |
| Modern / relative four giants | 4.5625 | 83664.737 | 84433.431 |
| Modern / relative eight planets | 18.25 | 2974.051 | 3551.255 |
| Modern / relative eight planets | 9.125 | 633.151 | 841.404 |
| Modern / relative eight planets | 4.5625 | 310.710 | 371.425 |
| Modern / relative eight planets | 2.28125 | 262.363 | 334.504 |

For the frozen samples inside 1900–2100, original production at 146 days has maxima **207,124.438 km radial / 308,783.223 km vector**; the finest modern eight-planet replay gives **224.312 km radial / 270.199 km vector**. These do not supersede the larger maxima on the earlier 131-epoch characterization: the new sample populations differ. The remaining fine-step differences show that the last replay is not a mathematically converged error floor. Finer numerical integration, VSOP-versus-modern perturbator trajectories, FK5/ICRF differences, GM choices, test-particle dynamics, and omitted physics remain coupled in the residual.

## Blending and interpolation

The probe archives separate forward propagation from the left seed, backward propagation from the right seed, their direct linear blend at the requested epoch, and the production cached evaluation. At an internal exact seed, forward/backward diagnostics use the following segment; at the final diagnostic seed they use the preceding segment. Seed-only cache output remains exact. One-way endpoint residuals can therefore represent a whole 80-year interval, while the cached output is constrained by both endpoints.

Original production's forward and backward radial maxima are **590,599 km** and **700,241 km**, respectively, compared with **216,077 km** for its cached blend over all 25 epochs. With modern seeds and the finest eight-planet replay they are **639 km**, **1,338 km**, and **262 km**. Blending visibly suppresses some one-way residuals; that suppression is not proof that the propagation model itself is accurate.

The initial epochs lie on all step grids at 73 days or finer. Their almost-zero cached-versus-direct differences therefore establish node consistency only. Separate [near-node](../../Scripts/reference-data/sources/distance/model-diagnostics/pluto/offgrid/plan.json) and [phase-varied](../../Scripts/reference-data/sources/distance/model-diagnostics/pluto/phasegrid/plan.json) plans add twelve interior epochs each, plus the five seeds, before acquiring new references. The first attempted one-third-day offset could not round-trip through Horizons' printed JD precision under strict epoch equality; the unsuccessful plan is retained, and the next plan uses exact binary fractions. The phase-varied offsets sample substantial fractions of the original 146-day cells as well as distinct finer-cell phases.

The quantity named `interpolationVersusDirectBlend` is an operational cache-versus-direct-path difference. The direct path also replaces the final integration step with a shorter step to land exactly on the requested epoch, so this quantity includes that change to local numerical integration. It is not a uniquely isolated interpolation truncation bound. Both complete vectors and signed radial differences are archived, allowing alternative analyses without acquiring new data.

| Phase-varied replay | Step (days) | Maximum cache-versus-direct vector difference (km) | Maximum absolute radial difference (km) |
| --- | ---: | ---: | ---: |
| Original seeds / production forces | 146 | 48.185806 | 9.355406 |
| Original seeds / production forces | 73 | 23.308256 | 9.211765 |
| Original seeds / production forces | 36.5 | 6.518118 | 1.053539 |
| Original seeds / production forces | 18.25 | 0.243804 | 0.094656 |
| Modern seeds / relative eight planets | 2.28125 | 0.002608 | 0.000719 |

The initial plan's 146-day off-node samples near seed boundaries show a larger **547.745 km** maximum operational vector difference; the near-node interior extension gives **8.462 km**. These different populations demonstrate the dependence on both interval location and integration-cell phase. None of these sampled maxima is a continuous interpolation bound, but they are much smaller than the original hundreds-of-thousands-of-kilometres seed/propagation discrepancies.

## Reproduction and proof limits

All small responses, exact query recipes, plans, reports, and source hashes are under [`sources/distance/model-diagnostics/pluto`](../../Scripts/reference-data/sources/distance/model-diagnostics/pluto). Downloaded `TOP2013.dat`, `TOP2013.f`, and `TOP2013.ctl`, generated C variants, binaries, and the isolated Python environment remain in `.context/pluto-model`; the repository retains their source URLs and required hashes without redistributing the official evaluator or control files. [`pluto-model-diagnostic.py`](../../Scripts/reference-data/pluto-model-diagnostic.py) and [`pluto-diagnostic-probe.c`](../../Scripts/reference-data/pluto-diagnostic-probe.c) reproduce the experiments. Query parsing rejects changed targets, centers, solution tags, frames, time scales, units, epoch order, nonfinite states, malformed state lengths, and API signature changes. The manifest binds the driver/probe and the production source plus included coefficient/header files.

```sh
python3 Scripts/reference-data/pluto-model-diagnostic.py --check
python3 -m unittest discover -s Scripts/reference-data -p 'test_pluto_model_diagnostic.py'
python3 Scripts/reference-data/pluto-model-diagnostic.py
python3 Scripts/reference-data/pluto-model-diagnostic.py --forces
python3 Scripts/reference-data/pluto-model-diagnostic.py --convergence
python3 Scripts/reference-data/pluto-model-diagnostic.py --omission
python3 Scripts/reference-data/pluto-model-diagnostic.py --offgrid
python3 Scripts/reference-data/pluto-model-diagnostic.py --phasegrid
```

The first two commands are offline integrity, source-variant reconstruction, reference-contract, invariant, and residual-arithmetic checks. They do not recompile the trajectories. The remaining commands perform compiled trajectory replay against archived references and write newly reproduced diagnostic reports. `--acquire` explicitly reacquires modern responses; it is not needed for replay. Compiler/platform floating-point results may vary at rounding scale; archived hashes are exact-byte provenance, not portable mathematical invariants. Do not reseal changed scientific results without reviewing and documenting them.

To repeat TOP2013 evaluation on a new machine, download the official `TOP2013.dat`, `TOP2013.f`, and `TOP2013.ctl` from the exact URLs in `top2013-sources.json` into `.context/pluto-model`, verify all three recorded SHA-256 values, and install `pyerfa==2.0.1.5` in an isolated environment. With `gfortran` available, run that environment's Python with `Scripts/reference-data/pluto-model-diagnostic.py --top2013`. The script checks coefficient/source hashes, compiles the official Fortran routines with their own rotation, evaluates both matched TDB and historical numeric TT, and independently runs the unchanged official program against its control file. This optional full replay is separate from standard-library CI checks.

The evidence supports targeted engineering options for a later decision: modernize seed provenance, correct the prescribed-origin/force contract, include omitted planetary forces, and select a numerically justified integrator/interpolation scheme, or adopt a separately justified ephemeris model. It does not select among those options. Any production change still requires owner-selected useful-error limits, explicit center/time/frame contracts, fresh characterization, and a newly independent holdout. Neither these finite samples nor the existing distance policy establish continuous or product-wide accuracy.
