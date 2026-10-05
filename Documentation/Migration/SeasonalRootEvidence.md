# Seasonal roots, 1900–2130 TT

The fresh nominal reference finds all 924 equinoxes and solstices in the approved interval. Both public Delta-T models return the same identities, counts and chronological order. Every nominal comparison passes the unchanged strict `<60 s` timing target with the frozen 1 s numerical allowance. Full physical apparent-season qualification remains incomplete: the reference does not certify gravitational-deflection, frame-realization or ephemeris physical uncertainty. Issue [#81](https://github.com/heirloomlogic/AstronomyKit/issues/81) remains open.

| Reference definition | Public Delta-T model | Events | Maximum absolute TT error | Nominal failures | Numerical-envelope failures | Inconclusive envelopes | Failed reference controls |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Nominal LT+S reception direction | jpl-horizons | 924 | 9.070238471 s | 0 | 0 | 0 | 0 |
| Nominal LT+S reception direction | espenak-meeus | 924 | 9.070278704 s | 0 | 0 | 0 | 0 |
| Fixed-delay diagnostic | jpl-horizons | 924 | 1.072373986 s | 0 | 0 | 0 | 0 |
| Fixed-delay diagnostic | espenak-meeus | 924 | 1.072414219 s | 0 | 0 | 0 | 0 |

These results supplement the historical 804 minute-resolution seasonal rows in [SeasonPhaseEvidence.md](SeasonPhaseEvidence.md). They do not rewrite that archive or explain its 54 nominal failures by assumption. The fresh reference includes the previously uncovered 2101–2130 years and avoids minute-rounded UT labels.

## Prospective protocol

[seasonal-root-sampling-plan.json](seasonal-root-sampling-plan.json) was committed at `e8e27178` before any ephemeris acquisition. A pre-acquisition dependency correction at `f207fe49` replaced NumPy 2.2.6 with 2.3.5 because the former has no binary wheel for the installed Python 3.14 runtime. Selection, observables and numerical controls did not change. Acquisition tooling was committed at `4363c22e` before the first query. Every query receipt records its acquisition revision and binds its parameters, compressed and decompressed response bytes, and prospective plan with SHA-256.

Selection starts at JDTT 2415020.5 (1900-01-01) and stops at JDTT 2499391.5 (2131-01-01, excluded from event selection). Each observable has an independent four-day coarse grid; the final endpoint is sampled only to bracket the last interval. Increasing unwrapped longitude identifies crossings of 0°, 90°, 180° and 270°. Public event times never seed reference searches. Identity validation requires four ordered events in every TT calendar year, with exactly 924 events over the interval.

Each coarse root receives independent queries at offsets −600, −200, +200 and +600 s and a halved grid at −300, −100, +100 and +300 s. Directed cubic interpolation reuses the reviewed position/event root helper, including its monotonic-interpolant check. Quadratic/cubic and half-grid differences must each remain at most 0.05 s; coarse/fine differences must remain at most 120 s. Fresh queries at the refined root ±0.5 s must show a strict ascending sign bracket. These controls were fixed before acquisition. No envelope was changed after results appeared.

The 64 retained query/response pairs contain 60,668 vectors: 21,094 coarse, 7,392 fine and 1,848 direct-bracket rows per observable. Each reference has 924 roots and zero failed controls. Maximum coarse/fine differences are 4.327636958 s nominal and 4.328683019 s diagnostic. Maximum half-grid differences are 0.000080467 s for each. Maximum quadratic/cubic differences are 0 s nominal and 0.000080467 s diagnostic at double-JD resolution. The eight-decimal query JD quantization is below 0.001 s; it is covered by the declared 1 s numerical allowance. The allowance describes numerical comparisons, not physical source uncertainty.

## Observable definitions

The nominal source is fresh NASA/JPL Horizons Sun-center `10` relative to Earth-center `399`, `CENTER=500@399`, `TIME_TYPE=TT`, explicit JD `TLIST`, ICRF `FRAME` vectors in AU/day and `VEC_CORR=LT+S`. Returned metadata identifies DE441 for both bodies. The source provides light-time and stellar-aberration corrections. At each reception TT, pinned PyERFA 2.0.1.5 / ERFA 2.0.1 rotates the direction with `Rx(obl06 + deps06a) @ pnm06a`, using ERFA's passive x-rotation convention. This is the mean IAU2006 ecliptic plane with the true equinox longitude origin. It is independently implemented by ERFA, rather than by the package's native frame code.

[JPL's Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html#obsquan) identifies apparent geocentric solar ecliptic longitude as the Earth-season observable and distinguishes Earth's mean-of-date ecliptic plane from other-body seasonal planes. The construction uses [ERFA pnm06a](https://github.com/liberfa/erfa/blob/v2.0.1/src/pnm06a.c), [nut06a](https://github.com/liberfa/erfa/blob/v2.0.1/src/nut06a.c) and [the ERFA rotation convention](https://github.com/liberfa/erfa/blob/v2.0.1/src/rx.c). Algebraic controls verify `Rx(obl06 + deps06a) @ pnm06a = Z(+dpsi06a) @ ecm06`, orthogonality and the rotation sign. Substituting the earlier mean-equinox `ecm06` matrix is detected; that earlier geometric-event reference is insufficient for absolute apparent seasonal longitude.

The nominal construction is not equivalent to Horizons observer quantity #31. [Horizons vector corrections](https://ssd.jpl.nasa.gov/horizons/manual.html#output) specify LT+S without gravitational deflection, while the complete apparent observer output has additional corrections and an IAU76/80 frame realization. The experiment has no certified bound for these contributions or for DE441 physical uncertainty. Consequently, passing the nominal timing comparison does not establish a fully independent physical apparent-season acceptance result.

The fixed-delay diagnostic queries geometric Earth-center `399` relative to Sun-center `10`, negates that vector, and evaluates the independent date frame at reception TT minus `1 / 173.1446326846693` days. This follows the correction shape of public `Sun.position(at:)`: native `Astronomy_SunPosition` uses one-AU backdating, geometric Earth position and a frame evaluated at the adjusted time. The diagnostic shifts TT exactly; native `Astronomy_AddDays` shifts UT and recomputes TT. Their precession/nutation/frame realizations also differ. The diagnostic therefore identifies a close convention match without asserting bit identity or isolating individual approximation contributions. Its smaller residual cannot replace the nominal reference or change the approved target.

## Reproduction and receipt boundaries

[seasonal-root-assessment.json](seasonal-root-assessment.json) retains all 3,696 comparisons, signed TT errors, nominal strict-target booleans, numerical-envelope classifications, root controls, returned source metadata, source/raw SHA-256 bindings, compiler and isolated-runner manifest identity, reference environment, installed binary/metadata hashes and downloaded wheel hashes. The original first measured assessment remains byte-preserved as `Scripts/reference-data/sources/seasonal-roots/initial-assessment.json.gz`; the assessment records its original validator identity. The assessment and raw response archives remain unchanged; the separate replay provenance records the updated validator identity.

The public runner is a development-only isolated package built by the existing build script. Its new `seasonal-roots` operation returns public `Seasons.forYear` TT values directly without converting reference UT labels. The original minute-reference `seasons` operation and shipping package manifest remain unchanged. Production evaluators and native event code are unchanged. Both supported Delta-T models are queried explicitly; the maximum difference between their public TT seasonal times here is 0.000080467 s. This is evidence for these returned events, not a general Delta-T equivalence claim or a TT/TDB derivative claim.

Run the following from the repository root. Replay is offline; only the dependency installation accesses the package index. The acquisition command is intentionally omitted because retained receipts are the reviewable evidence.

```sh
python3 -m pip install --only-binary=:all: --target .context/accuracy-qualification/python-reference pyerfa==2.0.1.5 numpy==2.3.5
python3 Scripts/reference-data/build-accuracy-runner.py
python3 -m unittest Scripts/reference-data/test_seasonal_roots.py -v
python3 Scripts/reference-data/check-seasonal-public-runner.py
python3 Scripts/reference-data/qualify-seasonal-roots.py check
```

Replay reads the authenticated archived query epochs instead of regenerating acquisition inputs from platform-dependent coarse-root arithmetic. It checks the exact batch names/counts, target/time/frame/correction parameters, fixed-delay round trip, ordering and refinement offsets against independently recomputed roots. The relationship check allows only the frozen eight-decimal JD quantization plus floating-point JD rounding. Missing, duplicate, reordered or one-second-shifted samples are rejected. Raw bindings remain exact.

Before platform comparison, both saved and recomputed payloads must contain finite numbers; every signed residual must equal its actual/reference epoch difference, each strict/envelope classification must follow that residual, and summary counts/maxima must follow the events. Rebuilt public and reference epochs may each differ by at most 8.64 ms, with corresponding residual/control differences checked before normalization and every classification preserved. This replay tolerance is below the unchanged 1 s reference numerical allowance and does not replace any frozen refinement or acceptance control. The original measured assessment remains byte-preserved; [seasonal-root-replay-provenance.json](seasonal-root-replay-provenance.json) retains the reviewed historical validator binding. [seasonal-root-current-validator-provenance.json](seasonal-root-current-validator-provenance.json) separately binds the active validator, including explicit private-manifest assessment plumbing, to unchanged scientific inputs. The current checker authenticates the private build manifest before executing scientific work; it requires no legacy global runner package. Apple and Linux CI each build their own isolated runner and execute this replay; hosted completion remains separate from local Apple verification.

The controls reject raw/query/plan detachment, empty or non-JSON source responses, missing source rows, wrong target, TT/TDB or frame/correction substitution, report-summary/classification tampering, wrong-year or echoed requests, missing/duplicated/reordered events, nonmonotonic root selection and exactly-60-second acceptance. A one-minute injected time shift changes the strict comparison outcome. These checks validate the experimental machinery and do not add a standing release policy.

## Remaining evidence

The next scientific requirement is an independently sourced apparent-season definition with documented correction/frame uncertainty adequate to judge the unchanged timing target. This campaign provides complete nominal seasonal sampling and reproducible numerical controls, but cannot substitute a certified physical envelope. Other unfinished reference families and issue #81 criteria remain outside this unit. Native event implementation remains owned by [#92](https://github.com/heirloomlogic/AstronomyKit/issues/92) and its [#89](https://github.com/heirloomlogic/AstronomyKit/issues/89) dependency; this experiment introduces no event repair.
