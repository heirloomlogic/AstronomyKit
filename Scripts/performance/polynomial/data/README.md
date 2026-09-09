# Polynomial coefficients and shipping validity

Each `*.bin.gz` contains little-endian IEEE-754 doubles ordered by segment, Cartesian axis, and coefficient. Coefficient zero already includes its half weight. `*.valid` holds one byte per segment from the fit screen at a 2.5e-13 AU and AU/day component limit; the 413 zero bytes (Mercury 409, Venus 4) are the only disabled segments. `generation.json` pins the uncompressed coefficient and validity hashes, the grid for each body, and the fit revision.

The archive was fitted against, and qualified against, the compensated VSOP87B evaluator that ships with it; the fit revision recorded in `generation.json` is the pre-merge commit of that change, whose `astronomy.c` differs from the merged file only in its vendoring note. A fit must target the numerics it is qualified against, so the archive is not reproducible from any earlier engine revision.

`shipping-validity.json` lists segments that failed the full-model component regression budget of max(1e-12, |reference| × 1e-12), either in the 53-sample grid qualification of every segment or in the replay of the four frozen product request populations at their exact TT; both lists are empty for this archive. `integration-validity.json` lists segments excluded after downstream angular-strength regressions; it is also empty. The generated header combines all three masks; excluded segments use the full series at runtime. The hashes inside those two files identify the qualification and replay reports preserved on the `heirloomlogic/compensated-refit-campaign` branch.

Coverage is TT [-36524.5, 36889.5), from 1900-01-01 through the end of 2100. The last segment may extend past the interval, but the runtime never exposes its padded dates.

Regenerate or verify the compiled header:

```sh
python3 Scripts/performance/polynomial/embed.py
python3 Scripts/performance/polynomial/embed.py --check
```
