# Complete PLU060 center coverage

The native Pluto model uses the complete verified PLU060 interval: TDB days −73047.5 through +73046.5 from J2000, 1800-01-02 through 2199-12-30. All three SPK summaries cover this interval. Their polynomial padding does not extend the allowed source domain. The center-offset segments join at TDB +4748.5. The upper source endpoint is exclusive in the evaluator.

`generate-pluto-tables.py --kernel PATH` verifies the pinned 135,207,936-byte kernel SHA-256 `dfbb102491a26ed41ae08ca3f8963f22f0219df1d8f265ab87b9ad825a826fc6`, then embeds all 4,566 DE440 Pluto-barycenter records, 9,131 negated DE440 Sun records, and 48,698 PLU060 center-offset records. [plu060-evidence.json](plu060-evidence.json) records coverage, shapes, and payload digests. The decoded payload is 21,768,120 bytes, up from 12,583,800 bytes. Existing center coefficients, AU conversion, TT/TDB rate conversion, ICRF-to-EQJ bias, and summation order are unchanged in their former window. Legacy C tables remain separate diagnostic sources.

## Routing and blends

Pluto has its own source weight. It is zero outside the source interval, rises with the quintic smoothstep over the first 32 TDB days, stays one through TDB +73014.5, and falls over the final 32 days. Full center weight starts at TDB −73015.5. The two tapers are inside verified coverage, with no source extrapolation. In those tapers the center contribution is partial; this is not a claim of full center weight at the kernel edges. Elsewhere in the accepted TT ±1461000-day range, the model uses the qualified DE441 system barycenter. The existing MajorBodies barycentric origin remains unchanged.

For H = D + w(C − D), velocity includes w′(C − D). The code evaluates w in TDB and multiplies its derivative by dTDB/dTT. The quintic meets the outer model with zero first and second weight derivatives. Runtime tests invert TT/TDB at both edges, check the guard on each side, test every adjacent source-record seam, and difference the complete state through both blends.

[plu060-qualification.json](plu060-qualification.json) encloses the difference between the source center and the blended representation over every interval in the union of their record boundaries: twelve intervals per taper. The derivation restricts binary64 source polynomials with exact rational arithmetic, bounds their power coefficients and derivatives over [−1,1], and adds the existing DE441 representation bound and PLU060 coefficient-conversion bounds. It bounds the additional velocity term with max |dw/dTDB| = 1.875/32. The lower and upper taper position bounds are 9,262.168 km and 9,257.309 km; their rate bounds are below 9,650.659 km/TDB day. Conservative angular bounds are 0.005204′ and 0.005945′, below the unchanged 1′ acceptance limit. These loose enclosures bound model differences, not independent physical ephemeris error or every floating-point evaluation operation.

Across all source records, the center-offset norm bound is 4,737.090 km and its analytic-rate bound is 6,265.411 km/TDB day. The summed coefficient-conversion position bound is below 0.000001640 km; source evaluation tests separately compare the native Clenshaw arithmetic with independently parsed SPK states. No center bound is extrapolated beyond the kernel.

## Independent samples and retarded evaluation

The fixture contains 282 direct SPK states, including both source edges, the segment join, both blends, and uniform interior samples. Native position/rate tests use 0.0001 km and 0.00001 km/TT day limits after the explicit time and frame conversion. Nineteen new Horizons target-999 geometric samples retain the existing 1 km position gate and a 1e-8 relative-rate gate. The 29 older center vectors now all receive full center weight and pass their existing 1 km and 1e-8 relative-rate gate.

Fifteen new Horizons target-999 observer dates extend the frozen observer set to 41 directions. The original two publisher archives remain unchanged. The earliest new reception date is TT −73046.5, one day inside source coverage; the latest is TT +73045.5. Tests record the actual retarded TT and TDB, require positive center weight and source coverage at emission, and retain the 1′ astrometric and apparent direction gates. The archived measurements give the emission margin for every sampled observer. Outside the PLU060 interval, retarded Pluto evaluation still uses the separate DE441 coverage qualified in the preceding link.

Horizons rejects target-999 observer epochs after 2199-12-29 00:00:00.0003 TT, a day before the local SPK summary endpoint. Geometric references likewise stop within that available endpoint. Direct SPK fixtures qualify native source evaluation during the remaining day; no Horizons agreement is claimed there. Target-9 endpoint references do not establish physical-center accuracy outside PLU060. Sun-dependent angles retain the separate Sun endpoint restriction documented in [OBSERVER-QUALIFICATION.md](OBSERVER-QUALIFICATION.md); event timing and unsampled outer center velocity remain unqualified.

## Reproduction

The source URL and whole-file digest are in `plu060-evidence.json`. DE441 uses the pinned range cache and source identity from `de441-evidence.json`; this work does not claim its whole-file digest. The following commands reproduce coefficient generation and every blend enclosure from those verified sources:

```sh
python3 Scripts/generate-pluto-tables.py --kernel /path/to/plu060.bsp --check
python3 Scripts/qualify-pluto-center.py --kernel /path/to/plu060.bsp --cache /path/to/de441-ranges --check
python3 -m unittest Scripts/test_qualify_pluto_center.py -v
python3 Scripts/qualify-pluto-center.py --check
swift test --no-parallel --filter 'EnginePlutoCenterQualificationTests|EnginePlutoEphemerisTests|EnginePlutoHorizonsTests|EnginePlutoConsumerQualificationTests'
```

The offline check verifies the recorded source bindings and geometric archive; it does not rerun the full enclosure calculation. `--capture` explicitly replaces the new geometric archive and must be accompanied by a fresh qualification. Native resource measurements and their host limitations remain in [de441-native-evidence.json](de441-native-evidence.json).
