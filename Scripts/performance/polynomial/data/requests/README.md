# Frozen downstream request populations

Each file is a gzipped array of fixed-size little-endian records captured from an instrumented AstrologyKit build while it ran the named workload. They record every internal ephemeris request the workload actually made, so they cover epochs the 53-samples-per-segment qualification screen does not visit.

Record layout, 24 bytes, matching `Request` in the original capture harness:

| Offset | Type | Field | Meaning |
| ---: | --- | --- | --- |
| 0 | `uint32` | `thread` | Logical capturing thread |
| 4 | `int32` | `kind` | 0 position, 1 state, 2 heliocentric distance |
| 8 | `int32` | `body` | VSOP body index, 0–7, Mercury through Neptune |
| 12 | `int32` | `active` | 1 for timed work, 0 for preparation |
| 16 | `float64` | `tt` | Exact TT the evaluator consumed |

NumPy dtype: `[('thread','<u4'),('kind','<i4'),('body','<i4'),('active','<i4'),('tt','<f8')]`.

These were captured during the fallback-cost investigation, which found 127 active component misses in scoring and 9 in the week scan at epochs the sampled screen had passed. They are retained as a qualification population so a refit is checked against the epochs the product visits, not only against the grid.
