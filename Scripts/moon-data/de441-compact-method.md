# Compact DE441 Moon experiment

This experiment compares representations of the geometric ICRF Moon-minus-Earth vector across the accepted `|TT| <= 1,461,000` days. It changes no production code. The [owner decision for #184](https://github.com/heirloomlogic/AstronomyKit/issues/184#issuecomment-6068614411) keeps the accepted range and one-arcminute angular target; it does not set a storage or runtime ceiling.

## Results

The scan covered 730,501 records and 730,500 adjacent boundaries. The minimum source-distance lower bound was 123,649 km. The bounds below include discarded coefficients and coefficient encoding; the jump column is an exhaustive endpoint measurement, not a bound on evaluator arithmetic.

| Candidate | Encoded MiB | Maximum angular bound | Maximum rate bound, km/TDB day | Maximum position jump, km | Records exceeding 1′ bound |
|---|---:|---:|---:|---:|---:|
| Degree 3 Float32 | 33.44 | 4.730′ | 1,428 | 182.947 | 680,202 |
| Degree 5 Float32 | 50.16 | 0.029681′ | 19.620 | 1.535 | 0 |
| Degree 7 Float32 | 66.88 | 0.000890′ | 0.282 | 0.04625 | 0 |
| Degree 5 Int16 | 25.08 | 0.563394′ | 23.738 | 32.882 | 0 |
| Degree 5 shared endpoints | 33.44 | 0.501588′ | 39.085 | 2.92e-11 | 0 |

The shared-endpoint candidate is recommended for the next link's Swift integration and production measurements. It uses 69.2% less storage than the direct 108.68 MiB Float32 representation, leaves about half the one-arcminute budget available for the remaining error terms, and avoids the ordinary candidates' position/rate jumps. Its 18.073 km position bound and 39.085 km/TDB-day rate bound are conservative coefficient bounds. No new velocity-accuracy requirement is inferred from them. Degree 7 Float32 is more accurate but larger and still has measured position jumps of up to 46.25 m. Int16 is smaller but has jumps up to 32.882 km. Degree 3 fails the representation target on 680,202 records.

On the recorded macOS arm64/Python 3.14 host, generation plus qualification took 207.34 seconds with the source already cached. The shared-endpoint encoding microbenchmark processed about 48,000 records/s versus 992,000 records/s for packing direct Float64 coefficients. Warm decoded position/rate evaluation processed about 155,000 states/s versus 87,000 for the direct 13-term evaluator. These are single-run Python observations under concurrent local work; they exclude production binary decoding and do not establish Swift performance. Exact observations are retained in the JSON manifest.

## Source and reproduction

The input is the [official DE441 SPK](https://ssd.jpl.nasa.gov/ftp/eph/planets/bsp/de441.bsp), interpreted using the [NAIF type-2 SPK specification](https://naif.jpl.nasa.gov/pub/naif/toolkit_docs/C/req/spk.html#Type%202:%20Chebyshev%20(position%20only)). The tool reuses the direct assessment's DAF parser. Moon 301 and Earth 399 have matching four-day records relative to center 3. Subtracting their 13 coefficients per axis gives the geocentric vector in kilometers; differentiating with respect to TDB days gives its rate. The experiment neither applies an ICRF-to-EQJ rotation nor differentiates the TT-to-TDB mapping.

```sh
python3 -m unittest Scripts/test_assess_moon_de441.py Scripts/test_qualify_moon_de441.py -v
python3 Scripts/qualify-moon-de441.py
python3 Scripts/qualify-moon-de441.py --check
```

The generator downloads about 457 MiB of byte ranges and stores them under `.context/issue-184/compact/ranges`. Each response must match the pinned length, ETag, Last-Modified value, requested range, and any saved SHA-256. Cached ranges must match the committed manifest or their original receipt. The full 3.08 GiB kernel is not fetched, and its global digest is not claimed as verified. The generated candidate binaries remain in `.context/issue-184/compact`; their exact lengths and SHA-256 values are committed in `de441-compact-evidence.json`. `--check` regenerates all records and compares deterministic evidence, including binary digests and runtime checksums. Host details and timing observations are excluded from that equality check.

## Whole-interval bounds

For one coordinate, write the source polynomial as `p(x) = sum(c_n T_n(x))`, with `-1 <= x <= 1`. For decoded candidate coefficients `a_n` padded with zeroes, `|p-a| <= sum(|c_n-a_n|)` because `|T_n(x)| <= 1`. Its derivative error per TDB day is bounded by `sum(n^2 |c_n-a_n|) / 2`, because `|T_n'(x)| <= n^2` and each record is four days long. Combining the three coordinate bounds with their Euclidean norm gives vector position and rate bounds. Coefficient cancellation cannot reduce these bounds.

The source distance lower bound is `||c_0|| - sum(n>=1, ||c_n||)`, further reduced by the subtraction-rounding allowance. A nonpositive lower bound aborts qualification. A position-error ball of radius `E` around a source vector whose norm is at least `R` subtends at most `asin(E/R)`. The pass/fail comparison uses `E/R` against a downward-rounded sine of one arcminute. The printed angle is a diagnostic; it does not decide qualification.

Bounds assume IEEE-754 binary64 arithmetic with correctly rounded elementary arithmetic and square root. `math.fsum` and outward `nextafter` steps enclose reductions and squared norms. Each source coefficient receives a full ulp for the Moon-minus-Earth subtraction. These are bounds between the exact polynomials represented by the source and decoded candidate coefficients. They exclude production evaluator rounding, time-conversion error, frame transformations, and the physical uncertainty of DE441 itself. The later Swift integration must account for those terms; this experiment does not establish an end-to-end accuracy certificate.

All 730,501 records participate, including the two records that extend beyond the accepted endpoints to cover the TT-to-TDB margin. Record midpoint and radius, matching Moon/Earth grids, finiteness, total count, and adjacent epochs are checked. Both source segment pairs are included. Every one of the 730,500 adjacent boundaries is evaluated on both sides. The existing DE440 blend endpoints and the DE441 segment split are listed separately in the manifest. The 30 archived Horizons dates remain a separate sampled external-reference check.

## Candidate encodings

The ordinary candidates retain degrees 3, 5, or 7 and store the coefficients as Float32, or retain degree 5 as signed Int16 with fixed power-of-two kilometer scales `[16, 8, 1, 1/8, 1/64, 1/512]`. Int16 overflow aborts the experiment. Records are chronological, with x, y, then z coefficients, each in increasing degree order. Both source segments share one output stream. The manifest records the actual first record epochs, which differ from the clipped accepted-range endpoints.

The shared-endpoint candidate retains degree 5. Its binary begins with one position/rate node (six Float32 values: position xyz, rate xyz). Each 48-byte record stores its right position/rate node followed by c4/c5 for x, y, and z, also as Float32. The preceding record's right node supplies the left node, including at the DE441 segment split. The first node comes from the first source record's left endpoint. All other nodes come from the preceding source record's right endpoint. Source discontinuities are included in the coefficient comparison rather than assumed absent.

For each coordinate, endpoint position/rate values and c4/c5 uniquely determine the remaining coefficients. With `L,R` the positions and `VL,VR` the rates per TDB day, the reconstruction is:

```text
S = (R + L) / 2
O = (R - L) / 2
c2 = (VR - VL - 16*c4) / 4
c3 = (VR + VL - O - 24*c5) / 8
c0 = S - c2 - c4
c1 = O - c3 - c5
```

The velocity factors include the conversion from TDB days to the normalized coordinate. The polynomial is C1 in exact arithmetic with these shared nodes. Binary64 reconstruction introduces small endpoint differences; the exhaustive boundary diagnostics report the observed differences. Position and velocity continuity do not imply continuous acceleration. Tests cover mismatched neighboring source states as well as ordinary coefficients.

## Measurement limits

The manifest retains failed candidate counts and the first five failing record epochs, worst-bound epochs, all archived-reference residuals, encoded sizes and digests, source-boundary discrepancies, and candidate-boundary jumps. The generation timer includes projection, encoding, bound calculations, and boundary/reference diagnostics for all candidates together. A separate encoding microbenchmark compares each representation with packing the direct Float64 coefficients; it excludes network and source parsing. Evaluation timings use the same Python position/analytic-rate evaluator on warm decoded coefficients, excluding binary decoding and I/O. They compare this experiment's arithmetic workloads, not Swift throughput or application memory.

The representation recommendation is task-scoped evidence for link 3. Swift integration, production storage and runtime measurements, TT/TDB and frame handling, and independent end-to-end position/state/event qualification remain open. The existing #184 known issues stay in place.
