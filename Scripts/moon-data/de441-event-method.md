# Bounded native Moon event qualification

This final #184 chain link tests actual roots of native Moon event functions. It adds no production search API: #92 owns those ports, and #96 owns the public C-to-Swift cutover. #184 stays open. The tests establish agreement at published events and in twenty fixed windows; they do not establish full-range event completeness or absolute velocity accuracy.

## Source and windows

`generate-moon-events.py` extracts 358 direct Moon-minus-Earth DE441 records from the digest-verified cache used for the full-record representation qualification. `de441-event-fixtures.json` pins the link-2 evidence digest, ICRF frame, TDB coefficient scale, TT window scale, all coefficients, and independently summed midpoint states. The generator pins the resulting fixture digest. Its offline `--check` verifies the committed artifact, and `--check-source` rebuilds it against the verified source byte ranges. No compact-candidate coefficients enter the direct oracle.

The same generator archives NASA/JPL Horizons quantity 31 responses and exact queries for the Sun and Moon at 28 timestamps in January 2025. It derives four roots by linear interpolation inside one-minute apparent-longitude brackets and pins both response digests. The responses declare geocentric observer ecliptic longitude, UT timestamps, and corrections for light time, gravitational deflection and stellar aberration. The derived fixture records a one-second sampling allowance; the Swift qualification requires every phase root to agree within 15 seconds.

The selection is fixed before measuring event residuals: seventeen uniformly spaced 64-day windows reach from TT −1,460,999.75 to +1,460,999.75; two 96-day windows surround the 1900 and 2131 DE440 blends; a 64-day window surrounds the DE441 segment handoff at TDB −11,112.5. These are separated windows across the accepted range, not continuous coverage of all four millennia on either side of J2000. Coefficient selection includes a 0.01-day margin around each window for time conversion and bracket evaluation.

## Root harness

`MoonEventQualification` is test-only. Its direct evaluator uses forward Chebyshev sums and their analytic derivatives, independently of the compact evaluator's reconstructed Clenshaw recurrence. Every stored midpoint is compared against Python's `math.fsum` source evaluation. Both sources pass through the existing TT/TDB conversion and frame bias. The native side calls the integrated Moon state; no production algorithm is changed.

The harness scans half-day brackets for each quarter phase, ascending/descending node, and pericenter/apocenter. It rejects the phase discontinuity at ±180° and uses `Engine.Search.ascendingRoot` with a 1 ms numerical stopping tolerance. Reference and native roots are discovered separately, paired chronologically by window and event kind, and checked for equal detected counts and the expected crossing direction. The endpoint, blend and segment-handoff windows repeat discovery with quarter-day brackets and require root agreement within 0.01 s. That is a numerical repeatability check, not a physical event-time allowance or a proof that shorter-lived events cannot exist between samples.

Phase roots use a light-time-corrected Moon and `Engine.Positions.sunPosition` on both sides. The independent Horizons cases qualify the resulting apparent phase definition; the broad DE441 comparison still uses the same native Sun, orientation and TT/TDB implementations on both sides, so it measures the Moon representation and integration. Node roots use the same true-ecliptic frame transformation; the special 1903 Horizons case retains its original mean-ecliptic definition. Apsis roots use the radial velocity, and distances are evaluated at each source's own root. Shared orientation, TT/TDB and Delta-T implementations are not independently qualified by the broad comparison, and the fixed windows do not establish complete public event searches.

## Published tolerances and evidence limits

The twelve archived USNO phase labels are interpreted as UT with Espenak-Meeus, matching `AuditValidationTests`, and retain their 90 s allowance. The apparent definition puts the 2100-01-26 full moon at 92.084 s and the 2100-01-03 last quarter at 108.196 s from those minute-rounded labels, so those two rows remain explicit failures rather than receiving wider allowances. The six node and six apsis UTC references use their civil-time TT and retain 220.86 s for nodes and 2,100 s / 25 km for apsides. The two geometric 1903 Horizons cases retain 60 s. Those allowances apply to their established reference samples; they are not extended to every epoch in the accepted range.

Broad-window root shifts, root counts, and transition state residuals are recorded individually. No new universal event-time, velocity, storage or runtime ceiling is inferred. The 25 transition samples cover both sides of the four blend endpoints and the source-segment handoff; their position checks retain 1′ and 28.689 km, while velocity residuals are measured without adding an absolute velocity guarantee.

## Measured results

The [release evidence](de441-event-evidence.json) records 369 paired roots, 26 published-event comparisons, 25 transition samples, and the four source-bound apparent phase results. The four apparent cases pass 15 seconds with a measured maximum residual of 1.615 seconds. Two minute-rounded USNO phase rows do not meet the unchanged 90-second allowance, as described above; the largest phase error is 108.196 s. The largest node error is 50.563 s, the largest apsis time error is 107.545 s, and the largest apsis distance error is 9.986 km. Both special 1903 cases pass their separate 60-second checks.

| Broad-window event | Paired roots | Largest absolute shift from direct DE441 |
|---|---:|---:|
| Quarter phases | 184 | 6.796 s |
| Ascending/descending nodes | 87 | 8.555 s |
| Pericenter | 50 | 750.551 s |
| Apocenter | 48 | 104.294 s |

The largest sampled pericenter shift is about 12.51 minutes. This demonstrates why an angular representation bound alone cannot establish event-time accuracy. The transition samples reach 0.006836′ direction error, 7.142369 km distance error, and 4.946396 km/TT-day velocity residual. These measured maxima apply to the recorded samples, not every epoch.

## Reproduction

```sh
python3 Scripts/generate-moon-events.py --check
python3 Scripts/generate-moon-events.py --check-source
python3 -m unittest Scripts/test_generate_moon_events.py
MOON_PUBLISHED_EVENT_OUTPUT="$PWD/.context/issue-184/link4-published.json" MOON_SOURCE_EVENT_OUTPUT="$PWD/.context/issue-184/link4-source.json" MOON_TRANSITION_OUTPUT="$PWD/.context/issue-184/link4-transitions.json" swift test --no-parallel --filter EngineMoonEventQualificationTests
python3 Scripts/generate-moon-events.py --collect-results .context/issue-184/link4
```

The source replay needs the verified link-2 cache; ordinary CI uses the pinned fixture offline. Runtime measurements from link 3 remain applicable to unchanged production code. Production search behavior, public API integration and a decision about broader absolute state/event accuracy remain acceptance work for #92, #96 and #184.
