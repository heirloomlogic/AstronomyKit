# A measured route past the remaining station failure

**Implemented follow-up:** [Production integration and reviewed acceptance](../../PRODUCTION-INTEGRATION.md)
records the shipping model, civil-time contract, and paired AstrologyKit changes.
This document preserves the diagnostic evidence that justified that integration.

The model is no longer an unexplained blocker. The full VSOP87B + IAU2000B
candidate agrees with JPL-derived station times within about 8 seconds for all
12 frozen stations when compared at the same Terrestrial Time (TT). A separate
future-UTC experiment passes all 36 unchanged frozen events through the relinked
Swift probe. These are diagnostic results, not an integrated production release.

The recommended implementation is to retain the full model, correct the dated
planetary rotation, and implement an explicit, consistent civil-time contract.
Continue to define a station as zero change of apparent longitude. Do not tune
the physical model to reproduce the reference engine's returned speed field.

## Independent evidence

The local audit uses archived JPL Horizons apparent inertial directions,
quantity 45, for planetary-system barycentres observed from Earth's centre.
It transforms those directions with independent ERFA IAU2006 precession and
IAU2000B nutation, then finds the stationary longitude from local polynomial
fits. Neither AstronomyKit positions nor its rotation routine generates the
JPL reference. All evaluations use common TT, eliminating delta-T as an
explanation of these particular differences.

These choices follow the [Horizons quantity definitions](https://ssd.jpl.nasa.gov/horizons/manual.html)
and [Swiss Ephemeris's documented barycentre convention](https://www.astro.com/swisseph/swisseph.htm).
Mercury and Venus have no satellite distinction; Horizons resolves requests
1/2 to identifiers 199/299. Jupiter and Saturn must use 5/6, not 599/699.

Signed seconds below are each calculated station minus the JPL-derived station.
The original reference column uses the frozen returned-speed event converted
to TT using the original Swiss delta-T. It does not treat its ISO `Z` label as
proof of a correctly implemented UTC conversion.

| Event | Full model − JPL (s) | Frozen speed reference − JPL (s) |
|---|---:|---:|
| A07/0 | -0.296 | 3.478 |
| A07/1 | -0.414 | 3.447 |
| A08/0 | 0.479 | 8.718 |
| A08/1 | 0.307 | 3.275 |
| A09/0 | 0.567 | -10.569 |
| A09/1 | -0.068 | 12.028 |
| A10/0 | 6.747 | 9.556 |
| A10/1 | 7.154 | -0.995 |
| A11/0 | 6.587 | 68.966 |
| A11/1 | 8.008 | -40.933 |
| A12/0 | -0.343 | 3.743 |
| A12/1 | -0.342 | 3.485 |

At A11/0, differentiating Swiss's own longitudes gives a station about 13.8 s
from JPL, whereas its returned-speed root is about 69.0 s from JPL. This
supports the product's differentiated-longitude definition and locates much
of the prior failure in the oracle's speed convention. It does not establish
that all Swiss ephemerides, all speed flags, or all stations have this error.

The quoted milliseconds identify reproducible fit output, not millisecond
astronomical accuracy. Fits use seven samples over ±2 hours and degrees 2–4;
the report also includes a ±1-hour quartic fit. The largest JPL window change
is 0.679 s, at A11/0. This sensitivity does not explain a 69 s discrepancy,
but it is not a rigorous uncertainty bound. JPL includes gravitational light
deflection and a numerical ephemeris; the native candidate retains its prior
apparent corrections. The remaining several seconds need broader measurement,
not a fitted correction. These 12 local fits do not certify event discovery.

## The clock experiment

`AstroTime(Date)` currently maps civil time to the engine's UT value and derives
TT using a prediction of TT−UT1. UTC and UT1 are different time scales: UTC is
civil atomic time with leap seconds; UT1 describes Earth's rotation. Their
future relationship is not supplied by an extrapolation of TT−UT1 alone.

[IERS Bulletin C 72](https://hpiers.obspm.fr/iers/bul/bulc/bulletinc.dat)
and the [USNO TAI−UTC table](https://maia.usno.navy.mil/ser7/tai-utc.dat)
record TAI−UTC = 37 s from 2017-01-01. With TT−TAI = 32.184 s, this gives
TT−UTC = 69.184 s. Holding the last announced leap-second offset for future
UTC dates is the documented Horizons convention; it is not knowledge of
future leap seconds. Snapshots and checksums are in `time-data`.

At A11/0 the original native TT−UT estimate is 85.563 s. Replacing that with
the announced-offset convention changes the reported civil event time by
16.379 s, reducing the frozen discrepancy from −75.857 s to −59.477 s.
The value 69.184 is derived from the time standard, not selected from the
station residual. The frozen reference and 60-second tolerance stay unchanged.

The first experiment changes the default time conversion throughout the isolated C
library from the table's last effective date. It does not only overwrite a
reception-time TT field: light-time iteration and all internal time creation
use the same policy. Earlier dates keep the old policy in this experiment;
that shortcut is explicitly unsuitable as the final 1900–2100 time contract.
Earth rotation still approximates UT1 by the supplied civil days. Passing
six local house cases does not qualify future UT1 or all house calculations.

A second experiment keeps all three time scales distinct. Each civil input
becomes TT using the announced leap-second policy, then the existing native
TT constructor derives modeled UT1 using the unchanged delta-T approximation.
All internal native arithmetic and light-time calculations remain on that
consistent TT/UT1 pair. The Swift observations receive that `AstroTime` object.
This path also passes all 36 timing and convergence gates: maximum 59.478 s.
The six house/angle events now differ from their frozen references by 17.4–21.6 s,
showing that Earth rotation responds to the changed civil-time interpretation.
This is the preferred direction for the production time contract. It still uses
modeled UT1, not future measured Earth orientation.

A half-second margin against an oracle with an independently demonstrated
station discrepancy is fragile. The 36-event pass removes the immediate
experimental failure; it must not be advertised as 60-second absolute UTC
accuracy throughout 1900–2100.

## Implementation order and acceptance

1. Keep the full coefficient restoration and true-ecliptic-of-date observation
   path as the candidate. The independent station check supports both continuing
   this backend and retaining signed differences of apparent longitudes.
2. Implement civil UTC → TT using a versioned time table, with an explicit
   historical convention and last-announced future leap-second policy. Keep
   TT, UTC and UT1 semantics distinct. Audit constructors, inverse conversions,
   time arithmetic, search-return times and Earth-rotation calculations together;
   a global 69.184 s delta-T replacement is not the production implementation.
3. Run all 36 original records unchanged on the actual integrated production
   observations. Preserve the passing diagnostic as evidence, not as a substitute
   for that run. Keep the independent convergence gates separate.
4. Version the broader validation protocol before generating its 1900–2100
   cases: station roots must derive from apparent longitude, with matched body,
   frame and time definitions. Validate uncertainty against JPL. Preserve the
   original returned-speed records as an immutable regression set. Any change
   to the original acceptance oracle requires an explicit reviewed protocol
   decision; this investigation does not alter it.
5. Resume range, platform, sanitizer, performance and downstream migration
   qualification. Clear `B369-ASTRONOMY-60S` only after that production-backed
   acceptance record exists. Leave the remaining #369 event-search work open.

There is no current evidence requiring a replacement backend, a tolerance
increase, empirical speed offsets or speculative lunar/apparent corrections.
The next work is a time-contract implementation and validation protocol with
named conventions, rather than asking the product owner to choose an astronomy
formula.

## Reproduce

Use the existing model-matrix instructions first. The JPL diagnostic has pinned
Python-only dependencies; none becomes a shipping dependency:

```sh
.build/accuracy/oracle-env/bin/pip install -r Scripts/accuracy/requirements-horizons.txt
.build/accuracy/oracle-env/bin/python Scripts/accuracy/horizons_stations.py \
  Scripts/accuracy/results/followup/horizons .build/accuracy/full.dylib \
  --output .build/accuracy/station-audit.json
```

Re-evaluation uses archived requests/responses and verifies their hashes,
selected epochs, target, frame and time scale. It writes a separate report
with the local binary hash and fit results. To fetch a new independent snapshot,
use a separate output directory and explicit `--fetch`; do not overwrite the
accepted archive during ordinary verification.

```sh
python3 Scripts/accuracy/future_utc.py --output .build/future-utc \
  --products /absolute/path/to/AstrologyKit/.build/out/Products/Debug \
  --module-map /absolute/path/to/AstrologyKit/.build/checkouts/AstronomyKit/Sources/CLibAstronomy/module.modulemap \
  --require-pass
```

That command rebuilds the baseline four-model experiment, builds the separate
future-UTC variant and relinks the same Swift probe. It also generates a probe
whose three civil-time construction sites use the existing TT initializer with
the announced UTC offset, linked against the unchanged-delta-T full model.
Both experiments must pass all 36 timing and convergence checks. Without Swift inputs it reports 30 native
events, and `--require-pass` fails. The archived follow-up report records source,
native binary and Swift input hashes.

## Civil TT / modeled UT1 event results

Signed seconds for the second, three-time-scale experiment against the original
frozen records; every separate convergence gate passes.

| Event | Kind | Error (s) |
|---|---|---:|
| A01/0 | aspect | 1.329 |
| A01/1 | signIngress | 1.707 |
| A02/0 | aspect | 2.975 |
| A02/1 | signIngress | 2.399 |
| A03/0 | aspect | 2.002 |
| A04/0 | aspect | 4.134 |
| A04/1 | signIngress | 3.796 |
| A05/0 | aspect | 4.367 |
| A05/1 | signIngress | 2.193 |
| A06/0 | signIngress | 3.340 |
| A06/1 | aspect | 3.513 |
| A06/2 | signIngress | 2.379 |
| A07/0 | station | -1.865 |
| A07/1 | station | -1.930 |
| A08/0 | station | -5.678 |
| A08/1 | station | -0.489 |
| A09/0 | station | 13.662 |
| A09/1 | station | -9.413 |
| A10/0 | station | -0.166 |
| A10/1 | station | 10.903 |
| A11/0 | station | -59.478 |
| A11/1 | station | 52.010 |
| A12/0 | station | -0.928 |
| A12/1 | station | -0.644 |
| A13/0 | ascendantIngress | 18.253 |
| A14/0 | midheavenIngress | 19.066 |
| A15/0 | houseCrossing | 21.181 |
| A16/0 | angularBandCrossing | 20.858 |
| A17/0 | midheavenIngress | 21.593 |
| A18/0 | houseCrossing | 17.370 |
| A19/0 | solarBandCrossing | 8.654 |
| A20/0 | solarBandCrossing | -21.488 |
| A21/0 | solarBandCrossing | -2.451 |
| A22/0 | phaseBoundary | 5.193 |
| A23/0 | phaseBoundary | 4.389 |
| A24/0 | phaseBoundary | 4.843 |

## Verification status

All ten diagnostic tests pass, including frozen-reference identity and both
archived 36-event timing/convergence checks. The maintained command exits zero
with `--require-pass` for both clock experiments.
The existing 579-test shipping package result belongs to the prior experiment;
production sources have not changed in this follow-up, and no new full package
or platform run is claimed.

A fresh independent review could not start: the agent runtime returned
`agent thread limit reached`. No follow-up review verdict exists. The earlier
model-matrix review does not cover these new scripts or conclusions. Review
receipts are local in `.context/bug-bash-accuracy-followup.md`.
