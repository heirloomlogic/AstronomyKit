# Production accuracy integration

The integrated AstronomyKit and paired AstrologyKit observation path pass all
36 original events and the independent convergence gates. The maximum absolute
timing difference is 59.477844 seconds (A11/0). References and the 60-second tolerance
are unchanged. The limiting case has 0.522 seconds of tolerance margin under
the bundled future-UTC policy; every future time-table update must rerun this
gate. This is local ordinary-root acceptance, not completion of the
#369 search service or a universal UTC guarantee over 1900–2100.

The [before/after event table](Scripts/accuracy/results/production/events.md),
[machine-readable acceptance summary](Scripts/accuracy/results/production/summary.json),
and [artifact checksums](Scripts/accuracy/results/production/sha256.json) preserve
all 36 identities, timing errors, brackets, and angular/speed residuals.

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
`85f2d440f231902581dd40726e19072c6fe832a9`. The final production diagnostic
and paired tests both use the immutable SwiftPM checkout with no local dependency edit. The paired migration pins exact
AstronomyKit source commit
`c68b96cb87b20a49697af133921b8ad55b7e6ad0`. SwiftPM resolved an immutable
checkout through a gitignored local bare mirror, and all 76 shipping source
files matched the reviewed workspace. The committed manifest retains the public
GitHub URL. AstrologyKit commit
`92e7a773d1107a08efb3404d906b0323aef2f985` is on local branch
`astronomy-accuracy-integration`. The complete migration is also preserved in
[an applicable patch](Scripts/migrations/astrologykit-accuracy.patch), so it is
not available only inside a gitignored worktree. No release has been published;
both branches are prepared locally.

## Acceptance tooling

`Scripts/accuracy/production_gate.py` builds the paired checkout, verifies its
resolved dependency path and generated tables, and links the actual production
Swift/C objects. All model, date and coordinate diagnostic overrides are off.
It checks frozen event identities/counts, timing, brackets and residuals
separately. The report records source, object and module hashes. Run the
checked-in tool from the exact AstronomyKit checkout SwiftPM builds; it rejects
a different dependency path. On this macOS SwiftPM build layout:

```sh
python3 .context/AstrologyKit-migration/.build/checkouts/AstronomyKit/Scripts/accuracy/production_gate.py \
  --astrology .context/AstrologyKit-migration \
  --products .context/AstrologyKit-migration/.build/out/Products/Debug \
  --output .context/accuracy/accepted
```

The independent JPL station audit rerun against production C retains the
8.008-second maximum common-TT disagreement across the 12 stations. This
supports retaining speeds derived from apparent longitude. The civil-time
correction follows the independently sourced USNO/IERS time table: civil UTC
now determines TT, while delta-T still determines modeled Earth-rotation time.
The reference's returned-speed discrepancy is preserved in the
[component and JPL diagnosis](Scripts/accuracy/FOLLOWUP.md); no reference speed
or event timestamp was changed to obtain the pass.
The numerical goldens were refreshed only after that audit and the production
gate passed: 145 constants captured in one run, 144 changed. The unchanged
Moon phase-angle illumination constant also remains checked. These goldens
measure reproducibility; they do not replace independent astronomical references.

The broader selection is frozen in `Scripts/accuracy/RANGE-PROTOCOL.md` before
candidate evaluation: 24,120 monthly positions and 2,462 independently located
ordinary station roots over 1900–2100. Every one of the 2,462 station comparisons
is within 60 seconds; the maximum is 40.800 seconds. The reference difference-width
sweep moves a root by at most 3.988 seconds. That is a sensitivity measurement, not an uncertainty bound.
The monthly position comparison has a maximum longitude difference of 9.870
arcseconds (Pluto); per-body longitude/latitude residuals are archived. Common-TT
results do not establish universal civil UTC timing accuracy.

## Qualification status

- Independent review converged in **three rounds**, with no outstanding blockers
  or advisory findings. Fixes cover valid dates at delta-T discontinuities, a
  finite-input test assumption, and test isolation around the global delta-T
  setting. Critics requested Astra/high; the Fixer requested Sol/high. Runtime
  model confirmation and usage are unavailable. No escalations or reverts.
- Final serial debug and release each passed **591 tests in 176 suites**,
  including all bit-exact goldens and the added overlap regression. The
  time-boundary suite separately passed all 12 tests.
- ThreadSanitizer passed 590 tests in 176 suites without race warnings. This
  run precedes the final comments/test-only overlap correction; runtime code
  is identical. Tests run with `--no-parallel` because suite-level serialization
  does not isolate tests that change the process-global delta-T model. The
  thread-safety tests retain their own concurrent task groups.
- Paired calculation/fact/reference/cache tests: 137 tests in 12 suites passed.
  The full specification validator passed its 13 checks; 85 Python validator
  tests passed. Manifest validation reports `phase-passed` and preserves the
  pending evaluation suites; it does not claim release acceptance.
- Final iOS, tvOS, and watchOS generic builds passed with the reviewed inverse
  fix, alongside macOS debug/release. Linux debug/release reproducibility
  remains release qualification work.
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

`B369-ASTRONOMY-60S` is cleared for this reviewed candidate's local production
comparison. Remote tracker state is unchanged; release acceptance is separate;
#369's certified search, adapter and complete `ElectionEventTests` remain pending.
No independent frozen records, calibration letters or evaluation manifest have
been changed to absorb the model migration.
