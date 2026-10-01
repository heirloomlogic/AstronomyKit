# Geometric solar altitude: error budget checks

These scripts back the numbers in the DocC article `SolarAltitudeNumerics` (Sources/AstronomyKit/Documentation.docc), which explains each bound and how it was measured.

- `bounds.py` derives every bound that follows from the shipped sources, in exact rational arithmetic, and records them in `bounds.json` (`--write`) or verifies that file against the sources (`--check`). Coefficients copied from `astronomy.c` are asserted to still appear in the function they came from.
- `measure.py` measures the rest by comparing the shipped binary64 engine with a binary128 rewrite of the same source (`quad_transform.py`, `probe.c`). `--check` runs a reduced grid against the ceilings in `bounds.json`; `--help` lists the grid options the article used.
- `bounds.json` keeps the derived values under `computed` and the review-chosen ceilings under `measuredCeilings`. Change a ceiling only with a reason in the article.
- `test_bounds.py` checks the helpers, that every value the article quotes from `bounds.json` is current and rounded away from the exact value rather than toward it, that every value in `bounds.json` appears in the article, and that the recorded bounds cover the engine's inverse tolerance, the calendar arithmetic, and the Delta T pieces the coverage reaches.

MAINTAINING.md lists the commands; CI runs them on Linux, where GCC provides the libquadmath that `measure.py` needs (on macOS, Homebrew GCC works with `QUAD_CC=gcc-15`).
