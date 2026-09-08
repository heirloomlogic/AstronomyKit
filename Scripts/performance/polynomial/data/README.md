# Polynomial coefficients and shipping validity

Recovered without refitting from commit `860a674`. Each `*.bin.gz` contains
little-endian IEEE-754 doubles ordered by segment, Cartesian axis, and coefficient.
Coefficient zero already includes its half weight. `generation.json` pins the
uncompressed coefficient and original validity hashes. The original fit used
full-model revision `0129d8a494957f12be101916cf7f18f8bbde7622` and the preserved
`protocol-at-generation.md`; historical screening results remain in `860a674`.

`shipping-validity.json` separately excludes segments that fail the current
native full-model component regression budgets. Its qualification hash identifies
`../results/qualification.json`. The separate `integration-validity.json` excludes segments implicated by
downstream angular-strength regressions, with evidence in
`../results/integration-exclusions.json`. Original coefficient and validity files are
unchanged. The generated header combines these masks; no data is loaded at runtime.

Coverage is TT [-36524.5, 36889.5), from 1900-01-01 through the end of 2100.
The last polynomial segment may extend beyond this interval, but the runtime
never exposes its padded dates.

Reconstruct or verify the compiled header:

```sh
python3 Scripts/performance/polynomial/embed.py
python3 Scripts/performance/polynomial/embed.py --check
```

The original experiment protocol is historical. Shipping acceptance uses
`../../native-math/POLICY.md` and the current qualification report, including
full-model fallback, complete event-record comparisons, and unchanged independent
astronomical references.
