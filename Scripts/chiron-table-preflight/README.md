# Chiron source-table preflight

This directory independently captures and screens a Chebyshev table candidate for issue #253. It does not change AstronomyKit's runtime.

The pinned JPL Horizons queries request target `2060;`, center `500@10`, geometric ICRF vectors, JD TDB epochs, and km/km-per-second output. Every response must identify 2060 Chiron solution JPL#171 and the Sun from DE441. The source span is JD TDB 2415019.5 through 2506333.5 inclusive, or 1899-12-31 through 2150-01-03, which surrounds the current public runtime endpoints.

The fitter uses 2,403 uniform 38-day records, 38 interior daily source vectors per record, and a degree-15 Householder least-squares Chebyshev fit. Independent half-day source queries are aligned on the daily source grid; they repeat the daily epochs as a same-epoch query-consistency control and supply disjoint heldouts at each record's seams and five spread interior points. Training epochs are JD values ending in `.0`; selected heldout epochs end in `.5`. The table stores binary64 position coefficients in record, axis, degree order; velocity is the analytic derivative per TDB day.

Horizons' numerically integrated small-body vectors depend slightly on the query path. An offset 38-day recipe differed from the aligned half-day query by more than 1 km at the same epoch, despite the same solution, center, frame, clock, and units. That rejected recipe and response remain pinned as a negative control. The passing residuals qualify only the exact daily and aligned half-day source recipe recorded here.

## Recorded result

The committed replay fits 91,314 source epochs to 0.00000763 km in position and 0.000050131 km/day in analytic velocity. The aligned queries repeat all 91,314 training epochs and differ by at most 0.124334671 km and 0.000069784 km/day. Across 16,821 disjoint heldout comparisons, the table differs by at most 0.124360036 km and 0.000209916 km/day. The retained offset-query control differs by 7.093823612 km and 0.004133851 km/day.

The pinned archive contains 11,342 query bytes and 16,742,375 compressed response bytes representing 54,411,040 uncompressed response bytes. The candidate table has 115,344 binary64 coefficients in a 922,752-byte payload. A runtime can select one of 2,403 uniform records by flooring the TDB-day offset divided by 38, with endpoint ownership still to be specified in Link 2.

Run the offline replay and tests with:

```sh
python3 Scripts/chiron-table-preflight/preflight.py --check
python3 -m unittest Scripts/chiron-table-preflight/test_preflight.py
```

An intentional source refresh requires network access and replaces the pinned query and response set before deriving the table and report:

```sh
python3 Scripts/chiron-table-preflight/preflight.py --capture
```

The 1 km position and 1 km/day analytic-velocity limits are reversible screening criteria for this source foundation. Issue #253 asks for a stated kilometre-level bound but does not define these values as public API policy. The report measures archived heldouts in every record, all seams, and both endpoints. It does not prove a continuous-domain bound, the physical accuracy of JPL solution 171, or its future orbit uncertainty.

The report records the compressed source-archive size and the candidate binary64 coefficient payload. Runtime lookup latency, package/build cost, TT-to-TDB conversion, frame rotation, endpoint ownership, and public-route behavior remain work for Link 2 after PR #283 clears review and ownership.
