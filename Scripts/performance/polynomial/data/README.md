# Polynomial coefficients and shipping validity

Each `*.bin.gz` contains little-endian IEEE-754 doubles ordered by segment, Cartesian axis, and coefficient. Coefficient zero already includes its half weight. `*.valid` holds one byte per segment from the original fit screen. `generation.json` pins the uncompressed coefficient and validity hashes, the grid for each body, and the fit revision.

`shipping-validity.json` lists segments that failed the native full-model component regression budget of max(1e-12, |reference| × 1e-12) during qualification. `integration-validity.json` lists nine more segments excluded after downstream angular-strength regressions. The generated header combines all three masks; excluded segments use the full series at runtime. The hashes inside those two files identify the qualification and evidence reports archived in git history at the merge of PR #36.

Coverage is TT [-36524.5, 36889.5), from 1900-01-01 through the end of 2100. The last segment may extend past the interval, but the runtime never exposes its padded dates.

Regenerate or verify the compiled header:

```sh
python3 Scripts/performance/polynomial/embed.py
python3 Scripts/performance/polynomial/embed.py --check
```
