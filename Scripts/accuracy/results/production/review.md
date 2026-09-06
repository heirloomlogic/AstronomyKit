# Production integration review

Review converged in **three rounds**, with no outstanding blocking or advisory
findings. Critics were read-only by instruction; tool-enforced confinement was
not available. Root coordinated review and resumed packaging after convergence.

## Scope and outcomes

Round 1 used two fresh Critics covering correctness, specification, lifecycle
and error paths across AstronomyKit and the paired AstrologyKit observations.
The broad handwritten scope was 2,729 changed lines; generated coefficient and
input-table volume was recorded separately. Review found:

- Valid 1961/1986 civil dates could fall inside a positive discontinuity in the
  delta-T approximation and make the exact TT inverse oscillate until invalid.
  `Sources/CLibAstronomy/astronomy.c:1033` now snapshots the selected model,
  preserves requested TT, and bounds inversion with a documented gap policy.
- A test incorrectly assumed every enormous finite input must be invalid,
  although the legacy JPL model can return a coherent finite result.
- Tests changing the global delta-T model overlapped unrelated suites.
  `.github/workflows/test.yml:38` and the other qualification invocations use
  `--no-parallel`; concurrent task groups inside the thread-safety tests remain.

The first fix was 195 lines (+171/-24). Exact gap regressions failed first with
eight assertions; the subsequent serial debug suite passed all 590 tests.

Round 2 reviewed only that fix. It found the new unconditional later-UT overlap
claim was false at the 1900 negative jump. The second fix documents the actual
TT-seeded first-convergence rule in C/Swift and adds
`Tests/AstronomyKitTests/CivilTimeTests.swift:183`. It verifies both valid forward
roots and the selected earlier root. The false later-root expectation failed
first. This fix was 49 lines (+37/-12) and changed no executable solver code.
The civil UTC table's later-occurrence convention remains separate.

Round 3 was a fresh review of only those 49 lines and returned clean across all
four remits. Both fix sizes decreased. There were no rejected findings, reverts,
escalations, capability retries, unresolved findings or advisory findings.

## Dispatch receipt

All four Critic contexts requested `gpt-6-astra` with high reasoning because of
the numerical inverse and cross-repository state/provenance concerns. The Fixer
requested `gpt-5.6-sol` with high reasoning. Runtime model confirmation and
actual usage were not exposed by the harness; no cost inference is made.
The ceiling was six rounds; review converged at round three.

## Final validation

- Final debug and release: 591 tests in 176 suites each, including bit goldens.
- ThreadSanitizer: 590 tests in 176 suites, no race warnings. This precedes the
  final comments and one regression test; executable model code is unchanged.
- Paired immutable-checkout tests: 137 tests in 12 suites.
- Full specification validator: 13 checks; Python validators: 85 tests;
  native diagnostic tests: 10, with no skips.
- Final iOS, tvOS and watchOS generic builds passed, alongside macOS.
- Immutable production gate: 36/36, maximum timing error 59.477844 seconds.
- Final native common-TT audit: 2,462 stations and 24,120 positions; no station
  exceeded 60 seconds (maximum 40.799618 seconds).
- Final native JPL audit: 12 stations, maximum disagreement 8.008008 seconds.

Source/object hashes and archive closure were verified. Subsequent changes
were the exact revision pin, packaging, evidence/documentation, and one line
wrap. No frozen reference, tolerance, or calibration letter was changed.
Linux execution and the wider release qualification remain pending as listed
in the production integration report. No release or tracker update was made.
