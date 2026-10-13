# 2026 SVS lunar-obscuration source comparison

NASA SVS 5672 says that 96.3% of the Moon's disc is inside Earth's umbra at greatest eclipse on 2026-08-28. This artifact preserves that published datum and the repository's unchanged conditional nearest-0.1-percentage-point interval of `[0.9625, 0.9635]`. It does not establish an accuracy tolerance or a production defect.

## Result

The exact SVS convention cannot be reproduced from the published source material. The SVS page identifies DE421, LOLA, and the Five Millennium Canon of Lunar Eclipses as datasets, then says it does not retain further dataset details. It does not publish the state vectors, full-precision peak epoch, radii, limb treatment, projection, overlap algorithm, full-precision result, or rounding rule used for 96.3%.

The offline replay verifies the repository's pinned NASA and JPL archives, extracts the one Horizons row at JD TT 2461280.676452763, and independently applies the documented circular Danjon tangent-plane geometry. Its standard-library result is `0.962481599215371`, within `1.1e-14` of the archived 80-digit calculation `0.962481599215360765...`. The pinned native Debug and Release result is `0.9624960076659318`. Both remain below `0.9625`, so neither reproduces the conditional SVS print interval.

| Evidence | Ephemeris and epoch | Quantity | Result |
| --- | --- | --- | --- |
| [NASA SVS 5672](https://svs.gsfc.nasa.gov/5672/) | Names DE421; prints greatest eclipse as 04:13 UT | Moon-disc area inside the umbra | 96.3% |
| [NASA Five Millennium Catalog](https://eclipse.gsfc.nasa.gov/LEcat5/LE2001-2100.html) | VSOP87 Sun, ELP-2000/82 Moon; 04:14:04 UT | Umbral magnitude, a diameter fraction | 0.9299 |
| [JPL Horizons](https://ssd.jpl.nasa.gov/horizons/) replay | DE441 apparent ICRF directions; JD TT 2461280.676452763 | Circular Danjon Moon-disc area | 0.962481599215371 |
| Pinned native capture | Repository apparent-input model at its selected peak | Circular Danjon Moon-disc area | 0.9624960076659318 |

The catalog's 0.9299 cannot be substituted for the SVS area percentage: NASA defines lunar umbral magnitude as the fraction of the Moon's diameter covered by the umbra, while SVS explicitly defines 96.3% as covered area. The catalog's VSOP87/ELP-2000/82 model and 04:14:04 UT peak also cannot establish the DE421 visualization's states or its printed 04:13 minute. The DE441 Horizons calculation is an independent arithmetic control on specified inputs, not evidence of DE421 agreement.

## Reproduce

Run the deterministic offline checks from the repository root:

```sh
python3 Scripts/svs-lunar-obscuration/replay.py --check
python3 -m unittest Scripts/svs-lunar-obscuration/test_replay.py
```

`source-receipts.json` binds the archived SVS page, Five Millennium Catalog page, Horizons queries and responses, independent 80-digit comparison, and native Debug/Release capture to SHA-256 digests at base revision `3c31e2d56eb4e887554ea185f5f75bdb78b3a674`. The NASA pages were checked live on 2026-10-13. The catalog bytes still matched the archive; the SVS page bytes had changed while the datum, dataset list, and missing-detail disclaimer remained present, so the replay uses the reviewed repository archive rather than silently replacing it.

`results.json` is generated only by `replay.py --write`. `--check` rejects source-byte drift, query-response mismatches, missing source statements, changes to the derived comparison, and an unexpected match to the printed interval. The unit tests also reject confusing diameter magnitude with area obscuration, substituting the catalog time for the SVS printed minute, or treating DE441 as the named DE421 source model.

## Qualification boundary

The missing SVS inputs prevent attribution of the `0.0000039923340682` native shortfall to ephemerides, distance, shadow enlargement, lunar limb/topography, peak selection, projection, overlap arithmetic, or rounding. Issue #275 should remain open unless those source conventions become available. The existing datum, interval, known-issue assertion, and broader #93 eclipse decisions remain unchanged.

NASA authored the source pages and JPL Horizons responses. This repository stores factual extracts and hashes with attribution; see [NASA's media usage guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/) for reuse conditions. AstronomyKit's replay code and transformed result remain under the repository license.
