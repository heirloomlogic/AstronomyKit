# Production accuracy integration

The integrated AstronomyKit and paired AstrologyKit observation path pass all
36 original events and the independent convergence gates. The maximum absolute
timing difference is 59.477844 seconds (A11/0). References and the 60-second tolerance
are unchanged. This is local ordinary-root acceptance, not completion of the
#369 search service or a universal UTC guarantee over 1900–2100.

## Production changes

- Shipping C uses all retained VSOP87B terms and 77-term IAU2000B, preserving
  the deterministic math and thread-safety patches. Positions and analytic
  derivatives share the full tables. Moon, Pluto, light-time, aberration and
  delta-T models remain unchanged.
- Civil `Date`, calendar and `now` construction uses the checksummed USNO time
  table; the native engine retains modeled UT1/TT. Native search results use
  the same civil inverse. Numeric UT1 archives and UT1 day arithmetic remain
  supported. Positive UTC gaps clamp to the following transition; historical
  overlaps choose the later civil occurrence. Future UTC retains the last
  announced leap-second offset; earlier-than-1961 dates retain the UT1 proxy.
- The native TT inverse snapshots one delta-T model and terminates on invalid
  inputs. Positive model discontinuities preserve requested TT and select the
  first representable UT1 after the jump. In negative overlaps, fixed-point
  iteration selects the first solution reached from its TT-seeded estimate.
  This is separate from the civil UTC table's later-occurrence convention.
- AstrologyKit derives planetary longitude and latitude from the same apparent
  geocentric vector in the true ecliptic of date. Dedicated Sun/Moon entry points
  and signed central-difference speed width remain unchanged. Fact provenance
  reads `AstronomyConfig.ephemerisVersion`; per-scan caches are in-memory values,
  so there is no persistent internal cache to migrate. Consumers must invalidate
  stored, version-dependent results and review their production snapshots.

The paired checkout is `.context/AstrologyKit-migration`, branch
`astronomy-accuracy-integration`, based on AstrologyKit
`85f2d440f231902581dd40726e19072c6fe832a9`. SwiftPM's local edit points it at this
AstronomyKit workspace during integration. The paired migration will pin the exact reviewed source commit before handoff.
No release has been published; both branches are prepared locally.

## Acceptance tooling

`Scripts/accuracy/production_gate.py` builds the paired checkout, verifies its
resolved dependency path and generated tables, and links the actual production
Swift/C objects. All model, date and coordinate diagnostic overrides are off.
It checks frozen event identities/counts, timing, brackets and residuals
separately. The report records source, object and module hashes. On this macOS
SwiftPM build layout:

```sh
python3 Scripts/accuracy/production_gate.py \
  --astrology .context/AstrologyKit-migration \
  --products .context/AstrologyKit-migration/.build/out/Products/Debug \
  --output .context/accuracy/integrated
```

The independent JPL station audit rerun against production C retains the
approximately 8-second maximum common-TT disagreement across the 12 stations.
The numerical goldens were refreshed only after that audit and the production
gate passed: 145 constants captured in one run, 144 changed. The unchanged
Moon phase-angle illumination constant also remains checked. These goldens
measure reproducibility; they do not replace independent astronomical references.

The broader selection is frozen in `Scripts/accuracy/RANGE-PROTOCOL.md` before
candidate evaluation: 24,120 monthly positions and 2,462 independently located
ordinary station roots over 1900–2100. Every one of the 2,462 station comparisons is within 60 seconds; the maximum
is 40.800 seconds. The reference difference-width sweep moves a root by at most
3.988 seconds. That is a sensitivity measurement, not an uncertainty bound.
The monthly position comparison has a maximum longitude difference of 9.870
arcseconds (Pluto); per-body longitude/latitude residuals are archived. Common-TT
results do not establish universal civil UTC timing accuracy.

## Qualification status

- Independent review converged in **three rounds**, with no outstanding blockers
  or advisory findings. Fixes cover valid dates at delta-T discontinuities, a
  finite-input test assumption, and test isolation around the global delta-T
  setting. Critics requested Astra/high; the Fixer requested Sol/high. Runtime
  model confirmation and usage are unavailable. No escalations or reverts.
- Serial debug passed 590 tests in 176 suites after the solver fix; the final
  added overlap regression passed in a 12-test focused run. Final full debug
  and release runs are being archived.
- ThreadSanitizer passed 590 tests in 176 suites without race warnings. This
  run precedes the final comments/test-only overlap correction; runtime code
  is identical. Tests run with `--no-parallel` because suite-level serialization
  does not isolate tests that change the process-global delta-T model. The
  thread-safety tests retain their own concurrent task groups.
- Paired calculation/fact/reference/cache tests: 137 tests in 12 suites passed.
  The full specification validator passed its 13 checks; 85 Python validator
  tests passed. Manifest validation reports `phase-passed` and preserves the
  pending evaluation suites; it does not claim release acceptance.
- iOS, tvOS, and watchOS generic builds passed before the bounded inverse fix.
  The final macOS build exercises that fix. Linux debug/release reproducibility
  and final Apple SDK rebuilds remain release qualification work.
- Both offline generators verify their checked-in output. All 10 diagnostic
  tests pass when supplied the compiled production library, including the
  independent ERFA nutation check.

## Measured cost and remaining release work

An initial optimized native C benchmark measured five trials of 1,600 mixed
planetary positions: median 0.196 seconds before and 14.209 seconds with full
coefficients (72.4×). The diagnostic dynamic library grew from 230,368 to
1,075,496 bytes (4.67×). This used a heavily contended Mac and Python/ctypes;
it is a preliminary cost measurement, not a production scan latency guarantee.
Full coefficients remain enabled. Production scan throughput, station-probe
runtime, peak memory, and a controlled final release benchmark remain required.

Release qualification also still needs Linux execution and the additional
preselected aspect, ingress, solar-threshold, lunar-phase and new JPL samples
from the wider plan. The monthly position and ordinary-station population is
complete; it does not certify complete event discovery. No tag, release, or
remote tracker state has been changed.

`B369-ASTRONOMY-60S` now has a passing integrated local comparison. Tracker
clearance and release acceptance must refer to the final reviewed evidence;
#369's certified search, adapter and complete `ElectionEventTests` remain pending.
No independent frozen records, calibration letters or evaluation manifest have
been changed to absorb the model migration.
