# Planetary source-model preflight for issue 248

DE441 plus the published URA184 physical-center offset misses the three retained Uranus Horizons apsis brackets by about +518.201, -665.357 and +475.683 TT seconds. Substituting the DE442 Uranus barycenter embedded in URA184, while retaining the archived DE441 Sun and the same center offset, reduces these measured residuals below 0.26 second. This diagnostic preserves the original 60-second allowance and source archives. It does not change the runtime model or satisfy issue 248.

The [owner decision](https://github.com/heirloomlogic/AstronomyKit/issues/92#issuecomment-6092259468) explicitly requires DE441 for Jupiter, Uranus and Neptune, the unchanged 60-second apsis target, and source-selected dense sampling over a complete cycle with every crossing preserved. The owner also prohibits shipping the remaining gap as a known issue. A task-specific source-model choice is pending; none of the diagnostic compositions constitutes an approved replacement or a standing policy. [Issue 248](https://github.com/heirloomlogic/AstronomyKit/issues/248) remains open, and its two planned implementation links remain unimplemented.

The official [URA184 part 3 comments](https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/satellites/ura184_part-3.cmt) identify its embedded Uranus barycenter as DE442. The retained Horizons response identifies target 799 as `ura184_merged` and the Sun separately as DE441. The sampled vector comparison distinguishes that mixed source from using the embedded DE442 Sun: the former differs by at most 0.000341 km, while the latter differs by about 0.200011 km. These are three sampled residuals, not physical accuracy bounds.

| Composition | Uranus root residuals from retained TT bracket midpoints | Maximum sampled position residual |
| --- | --- | --- |
| DE441 barycenter and Sun + URA184 center offset | +518.200953 s, -665.357102 s, +475.683091 s | 4200.600508 km |
| Embedded DE442 barycenter + DE441 Sun + same center offset | -0.046941 s, -0.254273 s, +0.224147 s | 0.000341 km |
| Embedded DE442 barycenter and Sun + same center offset | +0.045499 s, -0.373595 s, +0.309428 s | 0.200011 km |

The Jupiter and Neptune controls are in `evidence.json`. Jupiter's three DE441-based residuals are below 0.18 second. Neptune's two are approximately +17.896 and -18.927 seconds; its embedded DE442 composition reduces them below 0.15 second. These short-window results do not establish a complete-cycle gate for either body.

Run from the repository root with Python and mpmath 1.3.0 installed:

```sh
python3 -m unittest Scripts/test_planet_source_model.py -v
python3 Scripts/qualify-planet-source-model.py --check
```

`--check` verifies reproduction of the diagnostic, including the measured Uranus failure. An exit status of zero is not planetary acceptance. Without `--check`, the command prints a fresh JSON result to standard output; it never replaces an archive, fixture or report. `--verify-remote` additionally compares all pinned ranges and complete comments with their official URLs and HTTP identities. It also performs no file writes. A changed or unavailable source fails that optional online check.

`ranges.json` contains 79 byte ranges totaling 19,496 raw bytes from the official DE441, JUP365, URA184 part 3 and NEP098 part 1 kernels. Every range retains its byte offsets, SHA-256 and exact bytes. Each source retains its URL, HTTP total length, ETag when supplied and Last-Modified value. The complete satellite-kernel comments retain their own URLs and SHA-256 values. This is a range-based archive; no complete multi-gigabyte kernel digest is claimed. The diagnostic parses DAF summaries and type-2 metadata from the archived bytes, applies later-segment priority, checks target, center, frame, record midpoint and radius, and refuses missing ranges rather than fetching replacements during offline replay.

The state composition is barycenter minus Sun plus physical-center offset, on ICRF axes in kilometers. Direct Chebyshev recurrences evaluate position and velocity per TDB day. The input epoch and root brackets are TT. The clock uses the independently pinned ERFA `Scripts/apparent-place-data/dtdb.c` coefficients at 50 decimal digits; this file is a published reference copy, not a CLibAstronomy-owned generator input. The root solver bisects dot(position, velocity) divided by distance in TT to a bracket no wider than 0.0001 second. Multiplication by the positive TT-to-TDB rate would not change its zero. No apparent-place correction, Earth-relative origin, frame rotation or native planetary table enters this comparison.

The original 65-row Horizons responses and approximately 0.66-second refined root brackets remain in `Scripts/reference-data/sources/planetary-apsides` and `Scripts/reference-data/planetary-apsis-evidence.json`. The report records their exact input hashes. These are inherited native-centered eight-day windows, not the source-selected full-cycle census still required by the owner. The diagnostic samples vector agreement at each window's beginning, midpoint and end. It neither chooses principal extrema nor establishes absence of additional crossings. For example, the matched Uranus composition has a maximum sampled residual of 0.000341 km, or 0.341 m. These sampled differences are not bounds on physical ephemeris uncertainty.

This investigation reads existing source and reference files but adds no runtime input, generated table, public routing change, numerical certificate or measured-runtime report. Its validation consists of offline replay and mutation controls; it makes no new native build, performance, distribution-size or hosted-CI claim. The prospective table representation, full-cycle census and all eight public planetary trajectories remain implementation work after the source-model decision.
