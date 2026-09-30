# C bridge fuzzing

`fuzz_bridge.c` is a libFuzzer harness for the vendored Astronomy Engine C library in `Sources/CLibAstronomy/`. It decodes each input into times, bodies, observer coordinates, sky coordinates, a rotation matrix, and search limits, then calls the entry points the Swift layer forwards user-supplied numbers into:

- `Astronomy_HelioVector` and `Astronomy_GeoVector`
- `Astronomy_Equator`
- `Astronomy_Constellation`
- `Astronomy_Pivot`
- `Astronomy_SearchRiseSetEx` (the header's `Astronomy_SearchRiseSet` is a macro for it with `metersAboveGround = 0`)

Every call must return a known `astro_status_t`. A crash, an AddressSanitizer or UndefinedBehaviorSanitizer report, an unknown status, or a timeout is a finding. The harness does not check numerical accuracy; the Swift test suite does that.

Nothing here is part of the Swift package. `Package.swift` does not reference this directory, and `swift build` and `swift test` ignore it.

## Build modes

`build.sh` compiles `astronomy.c` and the harness in one of two modes. Both use `-fsanitize=address,undefined` with `-fno-sanitize-recover=undefined`, so the first UBSan report aborts.

```sh
sh Fuzzing/build.sh replay      # .build/fuzz/replay-bridge
sh Fuzzing/build.sh libfuzzer   # .build/fuzz/fuzz-bridge
```

`replay` links `replay_main.c`, a plain `main` that runs each file named on the command line (or each file in a named directory) through the harness once. It needs no libFuzzer runtime, so it works with Apple clang:

```sh
sh Fuzzing/build.sh replay
.build/fuzz/replay-bridge Fuzzing/corpus
```

`libfuzzer` adds `-fsanitize=fuzzer` and produces a real fuzzer. Apple clang ships no libFuzzer runtime, so this mode needs clang from LLVM: the one on Linux, or Homebrew's `llvm` on macOS (`CC=$(brew --prefix llvm)/bin/clang`). Fuzz into a scratch directory and pass the checked-in seeds as a second, read-only corpus, because libFuzzer writes new inputs into the first directory it is given:

```sh
CC=clang sh Fuzzing/build.sh libfuzzer
mkdir -p .build/fuzz/corpus
.build/fuzz/fuzz-bridge -timeout=25 -max_total_time=600 .build/fuzz/corpus Fuzzing/corpus
```

If Homebrew LLVM's AddressSanitizer runtime hangs at process start, as LLVM 21's did on the macOS 27 beta even for an empty program, build a libFuzzer binary with `-fsanitize=fuzzer,undefined` by hand for exploration, and replay what it finds with the Apple clang `replay` build to get the ASan check. CI runs the full libFuzzer build on Linux (below).

## CI

`.github/workflows/fuzz.yml` runs on ubuntu-latest every Monday at 06:00 UTC, on manual dispatch, and on pull requests that change `Sources/CLibAstronomy/`, `Fuzzing/`, or the workflow itself. It runs `make_corpus.py --check`, replays `corpus/` through the `replay` build, then builds the `libfuzzer` target with the runner's clang and fuzzes a scratch corpus with the seeds as the second corpus, as above. Scheduled and manual runs fuzz for 20 minutes; pull request runs for 2. A crash, sanitizer report, or timeout fails the job. Whatever libFuzzer saved, including `slow-unit-*` inputs that took over 10 seconds without failing, is uploaded as the `fuzz-artifacts` artifact. Download it and reproduce it as described below.

## Reproducing a finding

libFuzzer writes a failing input to `crash-*`, `timeout-*`, or `slow-unit-*`. Either binary reproduces it:

```sh
.build/fuzz/replay-bridge -timeout=25 crash-<hash>
.build/fuzz/fuzz-bridge crash-<hash>
```

`replay-bridge` takes libFuzzer's `-timeout=SECONDS` flag (default 25; 0 disables it) and aborts with the input's path when one runs longer. Each input resets the Delta T model and user-defined star 1 before it runs, so a finding reproduces from its file alone.

## Input format

Fields are read in a fixed order. Reading past the end of the input yields zero bytes, so any input decodes, including an empty one.

- A double is a tag byte and a payload. The tag's low two bits select the encoding: `0` is 8 bytes of raw little-endian IEEE 754 bits, `1` picks an entry from `SpecialValues` (NaN, infinities, `DBL_MAX`, subnormals, angle and hour boundaries, the Pluto table and crawl limits) using the tag's upper six bits, `2` is a 16-bit signed integer divided by 256, and `3` is a 32-bit signed integer.
- A body is one byte indexing `BodyValues`: every `astro_body_t`, then values outside the enum.
- An enum is one byte: 0 and 1 are the two valid values, and the rest are values outside the enum. The rise/set direction is the exception: its byte's low bit picks rise (0) or set (1).

The order is: flags (bit 0 builds the time from TT instead of UT, bit 1 selects the JPL Horizons Delta T model), user-defined star 1 (RA, Dec, distance), time, body, observer (latitude, longitude, height), `GeoVector` aberration, `Equator` equator date and aberration, constellation RA and Dec, rotation status byte and nine matrix entries, pivot axis byte and angle, rise/set direction, limit days, and meters above ground.

## Known defects excluded from fuzzing

The harness skips inputs that reach defects already tracked, so fuzzing can find new ones. Delete each filter when its fix lands.

- `RiseSetKnownHang`, [#57](https://github.com/heirloomlogic/AstronomyKit/issues/57): the rise/set search loops forever when `limitDays` is not finite and the body never crosses the horizon, or when the start time is so large that adding its 0.42-day step no longer changes it. Rise/set calls with `|limitDays| > 400` or `|ut| >= 2^52` are skipped. 400 days covers the Swift default of 366.
- `PlutoKnownUndefinedBehavior`, [#58](https://github.com/heirloomlogic/AstronomyKit/issues/58): Pluto at a NaN TT converts NaN to `int` in the state table lookup. Body calls for that combination are skipped.

Two more restrictions keep the rise/set search inside what the Swift layer can pass it. Neither is a tracked defect, because the package cannot forward these inputs:

- `SwiftAcceptsObserver`: Swift's `Observer.validatedRaw()` rejects non-finite coordinates and latitudes outside ±90° before any engine call, so the search only gets observers that pass the same check. With a non-finite longitude every altitude is NaN, and the search takes seconds to report no crossing. `Astronomy_Equator` still gets the unvalidated observer.
- Direction: Swift's `RiseSetDirection` is only rise (+1) or set (-1), so the harness only passes those. The C search does not validate direction, and any other value makes it search every step exhaustively (67 seconds for the Sun over 366 days).

## Seed corpus

`corpus/` holds 21 seeds that `make_corpus.py` writes. Their dates, bodies, observers, and coordinates come from `JPLValidationTests`, `AuditValidationTests`, `RiseSetTests`, `FixedStarTests`, and `RotationTests`, plus a few edge cases: the ends of the Pluto state table, a polar observer, and non-finite values. Change the input format and the seeds together:

```sh
python3 Fuzzing/make_corpus.py          # rewrite corpus/
python3 Fuzzing/make_corpus.py --check  # fail if corpus/ is stale
```

Don't commit libFuzzer's generated corpus. Add a seed to `make_corpus.py` when a fixed finding deserves a permanent regression input.
