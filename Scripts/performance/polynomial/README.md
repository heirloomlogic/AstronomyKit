# Polynomial planetary evaluation

For qualified segments from 1900-01-01 through the end of 2100 TT, the shipping engine evaluates degree-12 Chebyshev polynomials fitted to the complete VSOP87B model instead of summing the series. Position and heliocentric velocity come from one representation; heliocentric distance is the norm of that position. Dates outside coverage, and segments that failed qualification, fall back to the full series and its thread-local cache. Public APIs are unchanged.

Mercury and Earth use eight-day segments, Neptune sixteen days, and the other planets thirty-two days. The compiled tables add about 11 MB to the library.

## Files

- `data/` — the frozen coefficient archive and validity masks. See [its README](data/README.md).
- `embed.py` — renders `data/` into `Sources/CLibAstronomy/generated/polynomial-data.h`, verifying every input hash first. `--check` confirms the committed header is current; CI runs it.
- `test_polynomial.py` — analytic unit tests of the evaluator in `Sources/CLibAstronomy/polynomial.h`: exact quadratics for position and derivative, boundary rounding, invalid segments, and nonfinite dates.
- `work_probe.c` — used by `../test-vsop-cache.sh` to prove qualified fresh epochs never enter the trigonometric series.

```sh
python3 Scripts/performance/polynomial/embed.py --check
python3 -m unittest discover -s Scripts/performance/polynomial -p 'test_*.py' -v
sh Scripts/performance/test-vsop-cache.sh
```

## History

The fit, qualification, seam-check, downstream-trace, and benchmark harnesses, along with their raw results, were removed after the tables shipped. They live in git history under `Scripts/performance/polynomial/` at the merge of PR #36, and the original fit at commit `860a674`. Headline measurement from that campaign on an M1 Max: 1.4× faster day and week scans, 5.8× faster scoring, and 20× faster fresh-epoch position queries against the full-series engine, with every component within a 1e-12 relative regression budget.
