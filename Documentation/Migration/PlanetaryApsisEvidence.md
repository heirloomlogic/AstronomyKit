# Finite geometric planetary apsis evidence

The public planetary apsis API is not qualified by this investigation. Across the frozen 1900–2130 TT interval, the independent procedure found 3,546 raw geometric Sun-center range-rate crossings, resolved 3,383 roots, selected 3,380 orbit-scale candidates, and paired all 3,380 candidates with public events. It also retained 163 inconclusive roots, three boundary-clipped ambiguous clusters, and 62 public events without a resolved reference candidate. Six of the 3,380 paired events exceeded the unchanged strict 60-second target, all for Saturn. Issue #81 remains open.

The later [Saturn failure diagnosis](SaturnApsisDiagnosis.md) reproduces these scientific results and attributes the dominant six-case timing shifts to body-center versus system-barycenter motion, with separate model residuals. Its finer 1929 discovery grid exposes two additional raw crossings and limits that original pair's singleton identity classification. The original assessment remains archived; the later diagnosis does not qualify the family or replace its acceptance target.

The [sampling plan](planetary-apsis-sampling-plan.json) was committed before reference acquisition. It fixes the half-open interval from 1900-01-01 through the start of 2131 TT, all nine public planets including Earth and Pluto, and the intended observable: an extremum of geometric body-center distance from the Sun body center. No smoothing is applied. The comparison uses NASA/JPL Horizons vector table 3 with target body centers `199` through `999`, origin `500@10`, ICRF, TT, AU-D units, and `VEC_CORR=NONE`. The [Horizons API documentation](https://ssd-api.jpl.nasa.gov/doc/horizons.html) defines those request fields, the [Horizons manual](https://ssd.jpl.nasa.gov/horizons/manual.html) documents TT vector tables, and the [NAIF geometric-state documentation](https://naif.jpl.nasa.gov/pub/naif/toolkit_docs/C/cspice/spkgeo_c.html) defines an uncorrected target state relative to an observer.

The raw scalar is Horizons range rate relative to the Sun body center. A body-specific uniform coarse grid discovers sign crossings. Fixed five-point medium and fine queries refine each crossing. A root is eligible only when every stage has one directed crossing, the event kind remains stable, and the fine cubic-versus-quadratic difference is at most one second. Every rejected root, sample, and reason remains in the [assessment](planetary-apsis-assessment.json). The one-second allowance is a numerical diagnostic rather than physical source uncertainty.

Resolved raw roots are grouped only for this investigation. Adjacent roots separated by less than one eighth of the recorded mean orbit enter an experimental cluster. A singleton becomes an orbit-scale candidate; an odd alternating cluster may select its repeated-kind distance extremum. Other members would be recorded as additional local extrema. Even, nonalternating, or boundary-clipped clusters remain ambiguous and select no event. This diagnostic does not define production apsis identity. An unresolved root cannot be called either an intended orbital extremum or an additional local extremum.

## Results

| Body | Raw crossings | Eligible roots | Inconclusive roots | Orbit-scale candidates paired | Public events unpaired | Strict timing failures | Maximum paired error (seconds) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Mercury | 1,918 | 1,918 | 0 | 1,918 / 1,918 | 0 / 1,918 | 0 / 1,918 | 1.335096 |
| Venus | 751 | 751 | 0 | 750 / 750 | 1 / 751 | 0 / 750 | 24.198863 |
| Earth | 462 | 462 | 0 | 461 / 461 | 1 / 462 | 0 / 461 | 49.207056 |
| Mars | 246 | 246 | 0 | 245 / 245 | 1 / 246 | 0 / 245 | 11.658517 |
| Jupiter | 39 | 0 | 39 | 0 / 0 | 39 / 39 | 0 / 0 | — |
| Saturn | 16 | 6 | 10 | 6 / 6 | 10 / 16 | 6 / 6 | 356,596.961877 |
| Uranus | 5 | 0 | 5 | 0 / 0 | 5 / 5 | 0 / 0 | — |
| Neptune | 43 | 0 | 43 | 0 / 0 | 3 / 3 | 0 / 0 | — |
| Pluto | 66 | 0 | 66 | 0 / 0 | 2 / 2 | 0 / 0 | — |

The paired denominators distinguish timing evidence from unresolved event identity. Mercury has complete count, kind, order, and timing agreement. Venus, Earth, and Mars have one boundary-clipped cluster each, producing one unpaired public event per body while every eligible candidate pairs. Their paired timing results stay below 60 seconds. All six eligible Saturn candidates pair, but their nominal and one-second-envelope errors exceed 60 seconds; the worst is about 4.13 days. No paired event exceeds its unchanged body-specific distance threshold.

Jupiter, Uranus, Neptune, and Pluto have no eligible reference roots under the frozen refinement checks. Their public sequences remain ordered and alternating, but those properties do not supply independent event identities. Neptune's 43 and Pluto's 66 raw crossings are retained as inconclusive. The procedure does not silently choose a smoother observable or label these crossings as extra local extrema. Their zero additional-local-extremum counts mean no resolved root reached that classification.

## Endpoint and long-period diagnostics

The one-year opening and closing slices retain boundary behavior. Mercury has eight candidates and eight public events in each slice. Venus has three candidates and four public events in the closing slice. Earth has one candidate and two public events in the opening slice. Mars has no candidate and one public event in the opening slice. Saturn has one inconclusive root and one public event in the opening slice. All other opening or closing differences are recorded in the assessment.

The predetermined 2101–2130 slice includes all nine bodies. Mercury, Venus, Earth, and Mars respectively have 241, 94, 58, and 31 candidates matching the same public-event counts. Jupiter has five inconclusive roots and five public events. Saturn has two inconclusive roots and two public events. Uranus has no root or public event. Neptune has three inconclusive roots and one public event. Pluto has 47 inconclusive roots and one public event. These finite long-period observations do not establish a complete Neptune or Pluto orbit or resolve which raw crossings correspond to the public events.

## Provenance and reproduction

The 24 complete query/response pairs under `Scripts/reference-data/sources/planetary-apsides/` retain request parameters, response hashes, and the sampling-plan hash. Empty refinement populations are recorded as `not-queried` with a reason; they are not sent as empty Horizons requests. Coordinator protocol version 1 and its source hash are recorded separately from the premeasurement plan. The assessment binds 108 scientific inputs, including the shared Horizons parser and root helper, its clean candidate revision, Apple Swift 6.4, macOS 27.0.1 arm64, and runner SHA-256 `21709d96c27f77c646a7269b58263a13420a24ec9742bf98772a6393e74cd881`.

```sh
python3 Scripts/reference-data/build-accuracy-runner.py
python3 Scripts/reference-data/qualify-planetary-apsides.py check
python3 -B -m unittest Scripts/reference-data/test_planetary_apsides.py -v
```

The offline check replays the archived responses through the public APIs and compares every scientific field. It permits only the report's commit-time Git revision and dirty-state receipt to differ; source, archive, plan, executable, toolchain, platform, result, and failure changes remain report drift. Exact replay therefore requires the recorded compiler and platform. This investigation supplies finite sampled evidence rather than continuous accuracy, certified physical uncertainty, other event families, release behavior, or performance qualification.
