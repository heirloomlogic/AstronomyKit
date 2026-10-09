# Bounded native Moon event qualification

This final #184 chain link tests actual roots of native Moon event functions. It adds no production search API: #92 owns those ports, and #96 owns the public C-to-Swift cutover. #184 stays open. The tests establish agreement at published events and in twenty fixed windows; they do not establish full-range event completeness or absolute velocity accuracy.

## Source and windows

`generate-moon-events.py` extracts 358 direct Moon-minus-Earth DE441 records from the digest-verified cache used for the full-record representation qualification. `de441-event-fixtures.json` pins the link-2 evidence digest, ICRF frame, TDB coefficient scale, TT window scale, all coefficients, and independently summed midpoint states. The generator pins the resulting fixture digest. Its offline `--check` verifies the committed artifact, and `--check-source` rebuilds it against the verified source byte ranges. No compact-candidate coefficients enter the direct oracle.

The selection is fixed before measuring event residuals: seventeen uniformly spaced 64-day windows reach from TT −1,460,999.75 to +1,460,999.75; two 96-day windows surround the 1900 and 2131 DE440 blends; a 64-day window surrounds the DE441 segment handoff at TDB −11,112.5. These are separated windows across the accepted range, not continuous coverage of all four millennia on either side of J2000. Coefficient selection includes a 0.01-day margin around each window for time conversion and bracket evaluation.

## Root harness

`MoonEventQualification` is test-only. Its direct evaluator uses forward Chebyshev sums and their analytic derivatives, independently of the compact evaluator's reconstructed Clenshaw recurrence. Every stored midpoint is compared against Python's `math.fsum` source evaluation. Both sources pass through the existing TT/TDB conversion and frame bias. The native side calls the integrated Moon state; no production algorithm is changed.

The harness scans half-day brackets for each quarter phase, ascending/descending node, and pericenter/apocenter. It rejects the phase discontinuity at ±180° and uses `Engine.Search.ascendingRoot` with a 1 ms numerical stopping tolerance. Reference and native roots are discovered separately, paired chronologically by window and event kind, and checked for equal detected counts and the expected crossing direction. The endpoint, blend and segment-handoff windows repeat discovery with quarter-day brackets and require root agreement within 0.01 s. That is a numerical repeatability check, not a physical event-time allowance or a proof that shorter-lived events cannot exist between samples.

Phase roots use the same native Sun longitude on both sides. Node roots use the same true-ecliptic frame transformation; the special 1903 Horizons case retains its original mean-ecliptic definition. Apsis roots use the radial velocity, and distances are evaluated at each source's own root. Shared Sun, orientation, TT/TDB and Delta-T implementations make the broad comparison a measurement of the Moon representation and integration. It is not an independent qualification of those shared models or of complete public event searches.

## Published tolerances and evidence limits

The twelve archived USNO phase labels are interpreted as UT with Espenak-Meeus, matching `AuditValidationTests`, and retain their 90 s allowance. The six node and six apsis UTC references use their civil-time TT and retain 220.86 s for nodes and 2,100 s / 25 km for apsides. The two geometric 1903 Horizons cases retain 60 s. Those allowances apply to their established reference samples; they are not extended to every epoch in the accepted range.

Broad-window root shifts, root counts, and transition state residuals are recorded individually. No new universal event-time, velocity, storage or runtime ceiling is inferred. The 25 transition samples cover both sides of the four blend endpoints and the source-segment handoff; their position checks retain 1′ and 28.689 km, while velocity residuals are measured without adding an absolute velocity guarantee.

## Measured results

The [release evidence](de441-event-evidence.json) records 369 paired roots, 26 published-event comparisons, and 25 transition samples. All published cases meet their existing allowances: the largest phase error is 70.620 s, node error 50.563 s, apsis time error 107.545 s, and apsis distance error 9.986 km. Both special 1903 cases pass their separate 60 s checks.

| Broad-window event | Paired roots | Largest absolute shift from direct DE441 |
|---|---:|---:|
| Quarter phases | 184 | 6.783 s |
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
