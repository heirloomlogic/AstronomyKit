# Polynomial coefficients and shipping validity

Each `*.bin.gz` contains little-endian IEEE-754 doubles ordered by segment, Cartesian axis, and coefficient. Coefficient zero already includes its half weight. `generation.json` pins the uncompressed coefficient and original validity hashes.

The archive is refitted against full-model revision `8a1680535d7f4afc523dbe9e9041435dca9ddc10`, which compensates the VSOP series summation, and is qualified against that same revision with the polynomial path stubbed out so every reference sample takes the full compensated series. See `../PROTOCOL.md`. A fit must target the numerics it is qualified against: the earlier archive, recovered without refitting from `860a674`, was fitted against `0129d8a494957f12be101916cf7f18f8bbde7622` and qualified against a plain-summation build, whose own summation error exceeds the 1e-12 component budget. That archive is no longer reproducible from this protocol; its inputs and the preserved `protocol-at-generation.md` remain in git history.

`shipping-validity.json` excludes segments that fail the current component regression budgets, merging two populations: the grid qualification, whose report `../results/qualification.json` is identified by `qualificationSHA256`, and the request replay over `requests/`, whose report `../results/replay.json` is identified by `replaySHA256`. The separate `integration-validity.json` excludes segments implicated by downstream angular-strength regressions, with evidence in `../results/integration-exclusions.json`. Original coefficient and validity files are unchanged. The generated header combines these masks; no data is loaded at runtime.

Coverage is TT [-36524.5, 36889.5), from 1900-01-01 through the end of 2100. The last polynomial segment may extend beyond this interval, but the runtime never exposes its padded dates.

Reconstruct or verify the compiled header:

```sh
python3 Scripts/performance/polynomial/embed.py
python3 Scripts/performance/polynomial/embed.py --check
```

The original experiment protocol is historical. Shipping acceptance uses `../../native-math/POLICY.md` and the current qualification report, including full-model fallback, complete event-record comparisons, and unchanged independent astronomical references.
