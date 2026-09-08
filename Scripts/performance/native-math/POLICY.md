# Performance acceptance: native math and incremental delivery

Approved 2026-09-08. This policy supersedes the determinism, historical station
compatibility, and all-or-nothing performance gates for new candidates. Archived
reports retain their original protocols and results; none is retroactively passed.

- Ship native math on Apple and Linux. Both use shared numerical regression
  budgets and unchanged independent astronomical references. FP contraction stays
  disabled; complete model tables, time semantics and concurrency protections stay.
- Numerical fixture budgets: angles 1e-8 degrees (RA converted to hours), distance
  max(1e-12 AU, abs(reference)*1e-12), illumination 1e-14, existing rise/set and
  full-moon fixtures 0.01 seconds. Reject nonfinite outputs, wrap periodic angles,
  and preserve exact cache replay and metadata checks. These are regression
  budgets, not absolute accuracy claims.
- Keep independent event/station accuracy within the existing 60-second limit,
  existing position limits, convergence, event identity/count, coverage, unresolved
  reasons, cancellation, exhaustion, provenance and grouping validation. Historical
  station displacement is a reported diagnostic, not a 0.05-second veto. A local
  station probe alone does not certify event discovery or coverage.
- Deliver correct, measured improvements independently. Report the historical
  scoring/day/week target and downstream scoring cap separately; remaining misses
  do not reject a library improvement. Do not claim downstream release qualification
  from native throughput or aggregate checksums.
- Compile before timing; use five alternating Release trials. Archive commands,
  source/binary hashes, raw timings, complete window/event payloads and differences.
  Keep instrumented checks and profiles separate from timing.

Next increments address the polynomial evaluator, consistent apparent motion,
and downstream query identity/search costs. None blocks delivery of native math.
