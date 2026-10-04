# Retrospective assessment of the approved distance target

The owner initially approved uniform 1 ppm relative distance error over 1900–2130 TT on 2026-10-03, then approved a body-specific revision after reviewing model feasibility: 1 ppm for Sun/Earth/Mercury/Venus/Mars/Jupiter/Saturn, 10 ppm for Uranus/Neptune, and 100 ppm for Moon/Pluto. The current source-bound historical assessment contains no nominal exceedances of those revised limits. The revision reflects an explicit owner decision; it does not change the old frozen regression budgets, create a new independent holdout, or qualify the full interval.

[`approved-distance-retrospective.json`](approved-distance-retrospective.json) binds the approved policy, assessment script, original characterization, original acceptance report and historical allowances. It verifies every historical input hash, all 19 series, unique in-domain epochs, and complete 131/134-sample populations per series. The existing offline distance check separately recompiles the production probe and replays the historical acceptance report under its original policy.

## Results

The two prior populations contain 5,035 distance samples from 1900 through 2100 TT. The initial uniform 1 ppm assessment had 1,244 nominal exceedances: 612 in characterization and 632 in the prior holdout. The current approved body-specific assessment has zero nominal exceedances. These are non-exceedances rather than qualified accuracy passes because convention/reference uncertainty, new holdout independence and full 2101–2130 acceptance coverage are not settled by these samples.

| Body | Samples exceeding initial 1 ppm | All distance samples for body | Maximum nominal error | Current target |
| --- | ---: | ---: | ---: | ---: |
| Moon | 265 | 265 | 39.59 ppm | 100 ppm |
| Uranus | 227 | 530 | 3.33 ppm | 10 ppm |
| Neptune | 234 | 530 | 2.30 ppm | 10 ppm |
| Pluto | 518 | 530 | 34.93 ppm | 100 ppm |

The counts combine heliocentric and geocentric series for the planets; the Moon has only an instantaneous geometric geocentric series. The remaining archived series have no nominal exceedances of 1 ppm. Their lack of a sampled exceedance is not a continuous-domain or public-default-correction guarantee.

## Interpretation

The approved target compares absolute radial residual with `referenceRangeAU * 149597870.7 km/AU * epsilonBody`. It does not compare against old fixed kilometre allowances, apply the historical 2× characterization margin to the product target, or transfer a position-angle tolerance to distance. Moon residuals are geometric under its existing instantaneous exception. Received-light planetary rows retain their fixed-Sun origin bridge and approximation estimates; they do not establish exact equivalence with barycentric apparent range or the public default aberration behavior. Original model-center and vector-frame limitations remain explicit in [DistanceReferenceConventions.md](DistanceReferenceConventions.md).

These populations were observed before adopting the new product requirement. Even though the prior acceptance report was originally held out from the historical characterization, it is retrospective evidence for the later 1 ppm decision. A candidate repair needs newly chosen independent acceptance samples and explicit 2101–2130 coverage. A sampled exceedance under a retained convention approximation identifies an investigation target; the report does not supply a certified uncertainty budget or a fully isolated causal attribution.

The Sun-model decision remains to retain current production. The revised sampled distance assessment does not select a replacement for any body. Any later candidate must preserve the API's declared center/observable semantics and qualify positions/events as the primary use as well as the secondary distance requirement. [AccuracyQualificationPlan.md](AccuracyQualificationPlan.md) records that work and its boundaries.

## Reproduction

Use CPython 3.14.7. Run `python3 Scripts/reference-data/distance-accuracy.py check` to verify the historical source/query binding and recompiled 2,546-comparison acceptance replay. Run `python3 Scripts/reference-data/assess-approved-distance.py check` for the new offline retrospective policy assessment. `report` regenerates only the separate retrospective report; it never writes old characterization, allowances, acceptance or fixtures.

Run `python3 -m unittest discover -s Scripts/reference-data -p 'test_approved_distance.py' -v` for inclusive boundaries, sign, AU/km scale, exact body-specific policy mapping, rejection of unassigned-body fallback and invalid-input controls. These checks enforce the approved reporting requirement and assessment integrity; they do not qualify a production model, extend coverage, or establish hosted CI and independent numerical/code review.
