# Thread-safety upstream evidence

This directory isolates the four thread-safety changes carried in AstronomyKit's vendored `astronomy.c`: the Pluto cache and reset lock, the atomic Delta T function pointer, the atomic performance counters, and one-time constellation initialization.

Run `cd "$(git rev-parse --show-toplevel)" && sh Scripts/upstream/thread-safety/verify.sh` from anywhere inside the checkout. The script compiles the C probe directly with the current vendored source under ThreadSanitizer and runs one bounded stress case per fix. It then compiles the same probe with repository commit `42cc23924f404a4f35a4a3221dd8bf7ba8486da0`, the last AstronomyKit revision before any of these four fixes. Each negative process stops at the first report and passes only when ThreadSanitizer returns the configured status 66 with a matching race report. That repository commit's `astronomy.c` matches upstream Astronomy Engine commit `826e26ff3a6dc03ee46658b1138fef582d96c5d9` and remains unchanged at `865d3da7d8112bbc7911238052c6af4aaf877181`; its `astronomy.h` matches `865d3da7d8112bbc7911238052c6af4aaf877181`.

Set `KEEP_TSAN_ARTIFACTS=1` to retain the temporary sources, binaries, and full reports for inspection. The script prints their directory on exit.

The current source and one historical control are compiled without test hooks. The Delta T, Pluto, and counter modes run against that unchanged historical binary. The constellation race occupies only the first lazy initialization, and Apple clang 21 did not report its writer/writer conflict in 20 runs with 128 simultaneous callers even though all callers entered the initializer. A separate constellation-only binary modifies another temporary copy of the historical C source: it moves the two function-local static values to file scope without changing their storage duration and inserts a barrier after callers read the uninitialized status. ThreadSanitizer then reports two original initializer writes racing on `epoch2000`. This instrumentation-assisted result exercises the original write/write conflict after relocating its storage and adding the post-check barrier; it is not a direct report from the untouched historical source.

A clean bounded stress run is regression evidence for the exercised schedules. It does not prove that the implementation is race-free.

## Upstream state pinned on 2026-10-01

Upstream `cosinekitty/astronomy` still points `master` at `865d3da7d8112bbc7911238052c6af4aaf877181`. Open PR [cosinekitty/astronomy#402](https://github.com/cosinekitty/astronomy/pull/402) is based on that revision and changes only the Pluto cache construction inside `GetSegment`. It unlocks before `CalcPluto` reads the returned segment and does not lock `Astronomy_Reset`, so a concurrent reset can still race with use or free the segment. It also does not cover the Delta T pointer, performance counters, or constellation initialization.

PR #402 includes `<pthread.h>` without a Windows alternative. The upstream repository supports MSVC, so a contribution still needs an accepted synchronization design for Windows and POSIX builds. This evidence does not choose that design.

The local `PLUTO_MAX_CRAWL_DAYS` check is not part of this work. It changes behavior for dates outside the state table and should remain a separate upstream discussion.

## Remaining upstream work

Prepare an upstream patch against `865d3da7d8112bbc7911238052c6af4aaf877181` or its successor, preserve the lock across Pluto segment use and reset, supply Windows and POSIX synchronization, and rerun this harness against the rebased source. After upstream accepts equivalent fixes, AstronomyKit can refresh the vendored revision and remove only the corresponding local patches.
