# Polynomial evaluator experiment v1

Frozen before candidate evaluation. This is sampled qualification, not a formal
interpolation error bound. Shipping sources and astronomical references remain
unchanged until integrated acceptance.

- Source: the full VSOP87B evaluator at `0129d8a494957f12be101916cf7f18f8bbde7622`.
- Coverage: TT days [-36524.5, 36889.5), 1900-01-01 through 2101-01-01.
  An analytic calendar test caught an initial one-day excess at the upper bound.
  Removing it does not change the selected grids' coefficients or segment counts;
  final padded segments continue to be checked beyond the exposed coverage.
- Bodies: Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, Neptune.
- Grid: degrees 12/16/20/24; segment lengths 2/4/8/16/32 days.
  The final fit retains the full segment width (padding beyond coverage is never
  exposed by the runtime). Initial short-last-segment results are archived in
  `screen-short-last.json`; one-day fits amplified sampling roundoff in derivatives.
- Screening segments: first, last, and ten evenly distributed interior segments
  of each body's grid. No independent event reference participates in fitting.
- Fit: Cartesian heliocentric coordinates before VsopRotate, at 4*(degree+1)
  Chebyshev roots, projecting onto degree+1 coefficients after subtracting the
  midpoint position. Oversampling reduces differentiation of source roundoff;
  the original degree+1-node experiment is retained as `screen-single-node.json`.
  Full-range checks of this position-only fit found frequent velocity failures
  from differentiated source roundoff. The final fit projects the analytic full
  model velocity to degree-1, integrates it, and anchors position at the exact
  midpoint full-model position. Both runtime position and velocity still come
  from one polynomial. `--fit position` reproduces the rejected oversampled fit.
  No validation limit was changed in these corrections.
  Fixed-order double arithmetic with pinned deterministic trigonometry; coefficient
  zero uses the half-weight convention. Velocity differentiates the polynomial.
- Validation per segment: both endpoints, adjacent representable interior TT
  times, 31 equally spaced interior points, and 16 interior points from the fixed
  LCG seed 20260907. These differ from the interpolation nodes. Probe the full
  evaluator at exactly the representable TT consumed by the candidate.
- Screening component limits: 1e-11 AU position, 1e-11 AU/day velocity.
  These are preliminary filters; passing them cannot replace the event gates.
- Full-range validation applies the same samples to every selected segment.
  A failing segment uses the original evaluator and is counted in the report.
- Rank passing configurations by measured polynomial evaluation time; timings
  within 5% tie and use smaller coefficient bytes. Total binary coefficient data
  must not exceed 32 MiB. Report fallbacks and do not hide their timing cost.
- Final accuracy: unchanged 36-event/60-second gate, archived 24,120 monthly
  positions and 2,462 stations, JPL/Audit checks. Added root displacement from
  the full evaluator must be <=0.05 seconds for existing events and stations.
- Additional edge checks: both sides of every segment/coverage seam, central
  difference widths 0.0007/0.01/0.02/0.04 day crossing seams, non-finite/extreme
  times, repeated and concurrent calls. Preserve caller-owned time metadata.
- Performance: five alternating isolated trials, plus cold subprocess startup;
  random, chronological, refinement and repeated epochs. Downstream uses the
  preserved 320-scoring and five-minute New York day/week and Reykjavik day
  workloads, including preparation, plus the pre-change integrated gate.

No new numerical goldens or production model identifier until independent
accuracy and paired performance justify adoption.
