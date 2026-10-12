# Pluto DE441 feasibility

[Issue #252](https://github.com/heirloomlogic/AstronomyKit/issues/252) extends Pluto to TT ±1,461,000 days. The one-arcminute target approved in [#190](https://github.com/heirloomlogic/AstronomyKit/issues/190#issuecomment-6068625248) is unchanged. Its machine-readable result is [de441-evidence.json](de441-evidence.json).

## Candidate comparison

The experiment scans every DE441 source record intersecting the accepted TT range, expanded by the existing 2.2e-8-day TT/TDB margin and one day before the lower endpoint for light-time evaluations: 91,314 Pluto-barycenter records and 182,627 Sun records. Pluto uses 32-day, degree-5 polynomials; the Sun uses 16-day, degree-10 polynomials. Subtracting Sun (10 relative to SSB 0) from Pluto barycenter (9 relative to SSB 0) produces a heliocentric geometric state on ICRF axes in km and km per TDB day.

| Representation | Encoded bytes | Position bound, km | Analytic derivative bound, km/TDB day | Angular representation bound, arcminutes |
| --- | ---: | ---: | ---: | ---: |
| Direct Float64 | 61,362,744 | 0, apart from outward-rounding floor | 0, apart from outward-rounding floor | 0, apart from outward-rounding floor |
| Direct Float32 | 30,681,372 | 359.040 | 0.023048 | 0.000279279 |
| Shared cubic Float64 | 13,149,264 | 0.235244 | 0.134384 | 0.000000183 |
| Shared cubic Float32 | 6,574,632 | 435.412 | 46.005106 | 0.000338685 |

These are conservative representation bounds against the source polynomials, rounded upward for this table. They do not bound DE441's observational error, the unavailable full-range Pluto-center correction, or a future Swift evaluator's arithmetic. The derivative bounds concern each source interval and its one-sided endpoints; they do not establish accuracy for every state or event consumer.

The shipping shared cubic Float64 representation occupies 12.54 MiB. Shared nodes define a continuous position and first derivative in real arithmetic; the native integration evidence records every decoded seam. The wider source scan raises the conservative position enclosure from 0.234914 km to 0.235244 km and the derivative enclosure from 0.134200 to 0.134384 km/TDB day. These are computed representation certificates, not relaxed physical accuracy targets. This choice introduces no permanent size, speed, radial, or velocity policy.

On macOS arm64 with Python 3.14.7, the recorded 10,000-state measurements include indexing, packed-byte decoding, cubic reconstruction, and position/derivative evaluation of both bodies. Shared Float64 measured about 69,882 states/s versus 54,103 for direct Float64. Scan and encoding took 26.77 s versus 24.59 s. These Python observations do not describe production Swift performance; native measurements are recorded separately.

## Center versus barycenter

The complete existing archives contain 15 DE441 barycenter references across the accepted range and 29 `plu060_merged` center references from 1840 to 2159, including the current transition regions. All 44 are compared without selecting favorable dates. Direct Float64 agrees with the barycenter archive within 1.20e-6 km. Shared Float64 differs by at most 0.119586 km and 3.19e-7 km/s at those dates.

The manifest-pinned [PLU060 kernel](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/plu060.bsp) supplies Pluto center (999) relative to its system barycenter (9). Its [published comments](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/plu060.cmt) specify 1800–2199 coverage. The experiment verifies the whole kernel's existing SHA-256 and scans all 48,698 center-offset records over JD TDB 2378497.5–2524591.5. A coefficient bound gives a conservative offset norm of 4,737.09 km over that available coverage. It is not a bound outside that interval.

At the 29 center-reference dates, treating the barycenter as the center differs by up to 2,131.97 km, 0.091883 arcseconds, and 0.024273 km/s. Adding the available PLU060 offset to direct DE441 reduces the position residual below 2.14e-6 km; adding it to the shared Float64 candidate gives at most 0.090513 km and 3.09e-7 km/s. The archive agreement supports that particular source combination at those dates. Angular agreement alone does not make omitted center motion suitable for velocity consumers.

The conservative minimum heliocentric source distance is 4,419,554,543 km. With the shared Float64 representation bound, a hypothetical center offset below about 1,285,596 km would fit inside the one-arcminute geometric angular budget. That is a conditional calculation, not evidence that the offset stays within it over the accepted range. Full-range center accuracy remains open. The next link widens physical-center use within PLU060 coverage.

## Bounds and encoding

Each body retains its original record grid. Direct files contain little-endian coefficients, record-major, then X/Y/Z, each axis in ascending Chebyshev degree. Shared-node files contain one initial node followed by one right node per record; each node is X/Y/Z position followed by X/Y/Z derivative per TDB day. Float64 nodes occupy 48 bytes, Float32 nodes 24 bytes. Source coverage, grid spacing, record count, encoded size, and SHA-256 are recorded separately for each body and candidate.

For an interval of length h and normalized coordinate x, endpoint derivatives are multiplied by h/2. Write E = (pR+pL)/2 and O = (pR-pL)/2. The cubic Chebyshev coefficients are c2 = (dR-dL)/8, c3 = (dR+dL-2O)/16, c0 = E-c2, and c1 = O-c3. Each right encoded node becomes the following record's left node, including the DE441 segment join. Any source discontinuity is included in the next interval's coefficient error.

Outward-rounded interval arithmetic encloses the reconstructed coefficients. For coefficient-error bounds e_n, position error on an axis is at most Σ e_n because |T_n(x)| ≤ 1 on [-1,1]; derivative error per TDB day is at most (2/h) Σ n²e_n because |T'_n(x)| ≤ n². Outward Euclidean norms combine axes, and the two bodies' bounds are added. The minimum Pluto radius is bounded from its constant coefficient minus its tail norm, then the global maximum Sun radius is subtracted. The angular representation bound is asin(position error / minimum distance). Binary64 outward arithmetic and the final libm conversion are used; the tests separately check cubic interval enclosure against exact rational arithmetic.

In addition to all-record bounds and all seams, 72 fixed epochs cover accepted endpoints, a 58,400-day full-span grid, the DE441 segment join, and ±32-day neighborhoods of both central-model boundaries. These sample comparisons use TDB labels. They do not execute the production TT conversion, frame rotation, or blended Swift path, and are not an end-to-end transition qualification.

## Reproduction

The existing Moon DAF/SPK parser and range cache are reused without changing them. The DE441 HTTP identity and each retrieved range digest are pinned; the 3.08 GiB kernel's whole-file digest is not claimed. PLU060's whole-file digest is verified against the existing Pluto manifest. Candidate binaries are local artifacts and are not bundled into the library.

```sh
mkdir -p .context/issue-252
curl --fail --location --output .context/issue-252/plu060.bsp https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/plu060.bsp
python3 Scripts/assess-pluto-de441.py --cache .context/issue-252/ranges --plu060 .context/issue-252/plu060.bsp --artifacts .context/issue-252/candidates
python3 Scripts/assess-pluto-de441.py --cache .context/issue-252/ranges --plu060 .context/issue-252/plu060.bsp --artifacts .context/issue-252/candidates --check
python3 -m unittest Scripts/test_assess_pluto_de441.py -v
```

`--cache`, `--plu060`, and `--artifacts` override the local paths. A fresh cache downloads the needed verified DE441 byte ranges; an existing cache is rehashed before use. `--check` regenerates every record, candidate binary, bound, reference comparison, and fixed sample, then compares the evidence exactly except for the runtime-observation object. Runtime observations include the interpreter/platform and are deliberately excluded from reproducibility equality. CI runs the offline tests, including source/archive hashes, without downloading kernels; the full replay is a separate recorded validation.

The subsequent links integrated the selected representation and added bounded independent qualification. #96 then moved the public facade onto the native engine, and the archived center, blend, and outer epochs now gate the public Pluto route at their existing limits. This feasibility experiment remains evidence about representation, size, and runtime; it does not establish unsampled physical-center accuracy beyond the PLU060 coverage tracked by #252.
