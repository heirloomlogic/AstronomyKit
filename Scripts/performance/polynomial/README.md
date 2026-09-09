# Polynomial planetary evaluation

For qualified segments from 1900-01-01 through the end of 2100 TT, the shipping engine evaluates degree-12 Chebyshev polynomials fitted to the complete VSOP87B model instead of summing the series. Position and heliocentric velocity come from one representation; heliocentric distance is the norm of that position. Dates outside coverage, and segments that failed qualification, fall back to the full series and its thread-local cache. Public APIs are unchanged.

Mercury and Earth use eight-day segments, Saturn and Neptune sixteen days, and the other planets thirty-two days. The compiled tables add about 11.5 MB to the library. 413 of the 36,712 segments are disabled and use the full series: 409 for Mercury, clustered in 1900 to 1920 and 2060 to 2100 where |t| is largest, and 4 for Venus.

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

The first archive (PR #36) disabled 10,069 of its 34,418 segments. Those segments were not failing on fit error: `VsopCoords`, `VsopDeriv`, and `VsopHelioDistance` accumulated hundreds of series terms with plain addition, and because the t^1 longitude series begins with the mean-motion constant (26088 rad/millennium for Mercury, whose ulp is 3.6e-12), every later term rounded at that ulp and the loss was multiplied by t. The error is systematic and linear in |t|, reaching 4.45e-12 AU for Mercury at the coverage edges, so the max(1e-12, |reference| × 1e-12) qualification budget was measuring the full model's own arithmetic. Raising the fit degree changed nothing (Mercury width 2 screened at 4.148e-12 at degree 12 and at degree 24).

The engine now accumulates every series with Neumaier compensated addition, same terms in the same order, and matches a `math.fsum` evaluation of the same tables bit for bit. This archive was then refitted against that evaluator with the screening limit tightened from 1e-11 to 2.5e-13 AU and AU/day, four times inside the production budget. Every one of the 36,712 segments, including the 413 disabled ones, passes 53-sample qualification against the compensated full series with a maximum budget ratio of 0.41; the four frozen product request populations (2,974,191 unique epochs from scoring and the New York day, New York week, and Reykjavik day scans) pass with a maximum ratio of 0.15; 110,160 seam positions pass at 0.25; and no downstream integration exclusions remain. Against the previous archive on an M1 Max, the day scans run 4.7× to 5.6× faster, the week scan 5.0×, and scoring 1.9×; fresh-epoch position queries run about 420× faster than the compensated full series. The historical two-times product target remains unmet by 5.4× to 8.7×, and the remainder is downstream search rather than ephemeris evaluation.

The fit, qualification, request-replay, seam-check, downstream-trace, and benchmark harnesses for this refit, with their raw results and the frozen request captures, are preserved on the `heirloomlogic/compensated-refit-campaign` branch (tip `1add73e`); the PR #36 harness remains at that PR's merge commit, and the original fit at `860a674`.
