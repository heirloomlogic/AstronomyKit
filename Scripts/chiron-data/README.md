# Chiron table sources

`Scripts/generate-chiron-table.py` fits the Chebyshev table that `Engine.Chiron` reads, `Sources/AstronomyKit/Engine/Gravity/Generated/Chiron/ChironCoefficients.swift`, to the JPL Horizons responses pinned here.

The pinned queries request target `2060;`, center `500@10`, geometric ICRF vectors, JD TDB epochs, and km/km-per-second output. Every response must identify 2060 Chiron solution JPL#171 and the Sun from DE441. The source span is JD TDB 2415019.5 through 2506333.5 inclusive, or 1899-12-31 through 2150-01-03, which surrounds the public span of 1900-01-01 through 2150-01-01.

The fitter uses 2,403 uniform 38-day records, 38 interior daily source vectors per record, and a degree-15 Householder least-squares Chebyshev fit. Independent half-day source queries are aligned on the daily source grid; they repeat the daily epochs as a same-epoch query-consistency control and supply disjoint heldouts at each record's seams and five spread interior points. Training epochs are JD values ending in `.0`; heldout epochs end in `.5`. The table stores binary64 position coefficients in km, in record, axis, degree order; velocity is the analytic derivative per TDB day. Record `k` holds [start + 38k, start + 38(k + 1)), so the inclusive final endpoint lies outside the table and outside the public span.

Horizons' numerically integrated small-body vectors depend slightly on the query path. An offset 38-day recipe differed from the aligned half-day query by more than 1 km at the same epoch, despite the same solution, center, frame, clock, and units. That rejected recipe and response remain pinned as a negative control. The residuals below qualify only the exact daily and aligned half-day source recipe recorded here.

## Recorded result

The fit reproduces its 91,314 source epochs to 0.00000763 km in position and 0.000050131 km/day in analytic velocity. The aligned queries repeat all 91,314 training epochs and differ by at most 0.124334671 km and 0.000069784 km/day. Across 16,821 disjoint heldout comparisons, the table differs by at most 0.124360036 km and 0.000209916 km/day. The retained offset-query control differs by 7.093823612 km and 0.004133851 km/day. The table is 7.093823918 km from the offset-query control at most; the generator fails if any of the 108,136 archived epochs (91,314 training, 14,419 heldout and 2,403 offset) is more than 10 km from the table, the bound the public documentation states. The 1 km and 1 km/day screen limits apply to the training and heldout epochs only; `EngineChironTests` holds the runtime to 5 km against separately requested Horizons vectors.

The pinned archive contains 11,342 query bytes and 16,742,375 compressed response bytes representing 54,411,040 uncompressed response bytes. The table has 115,344 binary64 coefficients, a 922,752-byte payload compiled in as a 1,241,153-byte base64 Swift source.

## Commands

Refit the pinned sources and compare the committed Swift table and `report.json`, offline:

```sh
python3 Scripts/generate-chiron-table.py --check
python3 -m unittest Scripts/test_generate_chiron_table.py
```

`--write` refits and rewrites both. An intentional source refresh needs network access and replaces the pinned queries and responses before writing:

```sh
python3 Scripts/generate-chiron-table.py --capture
```

The heldouts cover every record, every seam and both endpoints, but finite samples do not establish a continuous-domain bound. Agreement with Horizons does not establish the physical accuracy or future orbit uncertainty of solution JPL#171.
