# Native Swift safety corpus

`Tests/AstronomyKitTests/NativeSafetyTests.swift` decodes every file in `corpus/` and sends its values through the public AstronomyKit facade. The harness covers native time construction, body and fixed-star positions, distances, observer coordinates, constellation lookup, rotations, rise/set and angular searches, lunar nodes, apsides, libration, coordinate storage, and gravity-simulation rollback. A typed `AstronomyError` is an accepted rejection; an unknown status, unexpected error, non-finite successful result where the public contract requires a finite value, negative successful distance, trap, sanitizer finding, or hang is a failure.

The same suite generates 512 deterministic byte inputs. Generated inputs use the historical byte schema, so the decoder exercises empty and truncated storage, every byte-derived index, special floating-point values, and arbitrary payloads without maintaining a second generator format. The gravity property separately proves that a rejected update does not change the simulation's time or body storage.

## Running the checks

```sh
python3 Fuzzing/make_corpus.py --check
swift test --filter NativeSafetyTests
swift test --sanitize=address --filter NativeSafetyTests
```

`.github/workflows/fuzz.yml` runs these commands on pull requests that change the native engine, the safety tests, this corpus, `Package.swift`, or the workflow. It also runs every Monday and on manual dispatch. Pull-request checkout is pinned to the pull-request head SHA, and the job verifies that revision before testing.

## Input format

Fields are read in a fixed order. Reading past the end yields zero bytes, so every input decodes, including an empty file.

- A double is a tag byte and a payload. The tag's low two bits select the encoding: `0` reads eight raw little-endian IEEE 754 bytes, `1` selects a maintained edge value with the tag's upper six bits, `2` reads a signed 16-bit integer divided by 256, and `3` reads a signed 32-bit integer.
- A body byte selects the historical C body's position in the old table. Native solar-system cases map to `CelestialBody`, star slots map to `FixedStar`, and invalid values still exercise body-independent native paths.
- Binary public enums use the same historical enum byte. Values that the Swift type system cannot represent map deterministically to one of its two valid cases.

The order remains: flags (TT instead of UT and JPL Horizons instead of Espenak–Meeus), fixed-star right ascension, declination, and distance, time, body, observer latitude, longitude, and height, aberration, equator date, a second aberration byte, constellation right ascension and declination, the historical rotation status byte, nine numeric values, pivot axis and angle, rise/set direction, limit days, and meters above ground. Keeping the format stable lets all 30 historical findings and boundary cases replay without regenerated fixtures.

## Seed corpus

`make_corpus.py` owns the exact set of 30 files. Their dates, bodies, observers, and coordinates come from the package's JPL, audit, rise/set, fixed-star, and rotation tests plus the Pluto table edges, accepted-time edges, a polar observer, and non-finite values. The seven `fixed-*` files retain the rise/set stalls from #57, Pluto's NaN input from #58, a huge longitude target, the far-time Neptune and Moon non-finite results, and Mars's former negative distance from #62.

```sh
python3 Fuzzing/make_corpus.py          # rewrite corpus/
python3 Fuzzing/make_corpus.py --check  # fail if corpus/ is stale
```

Add a named seed to `make_corpus.py` when a fixed finding needs permanent replay. Do not commit ad hoc generated inputs.

## Retired C checks and native replacements

| Retired check | Native disposition |
| --- | --- |
| `fuzz_bridge.c`, `replay_main.c`, and `build.sh` | Replaced by the public Swift corpus/property suite and its AddressSanitizer run. The harness now proves the package path used by consumers instead of the unused C target. |
| C/C++ CodeQL extraction | Replaced by Swift CodeQL on macOS with a manual `swift build --target AstronomyKit --arch arm64`. GitHub documents macOS as required for Swift extraction and supports both `swift build` and manual build mode. |
| C UndefinedBehaviorSanitizer | Removed. Swift.org documents AddressSanitizer and ThreadSanitizer for SwiftPM, but does not document UBSan as Swift instrumentation. ASan, TSan, Swift CodeQL, checked array access, generated properties, and strict Swift 6 checks cover specific native risks; they are not claimed as a complete UBSan equivalent. |
| C cache probe | Already replaced by the native cache identity and concurrency tests delivered for #95 in #239. The main test workflow retains those tests. |
| TSan suppression for `Astronomy_DefineStar` and `FixedStar.withSlot` | Removed because the native fixed-star implementation has neither symbol nor slot mutex. The TSan job now runs without project suppressions. |
| LeakSanitizer teardown suppression | Retained only for the known `libXCTest.so` allocation site and rewritten to describe native test coverage. It does not suppress an AstronomyKit frame. |

References: [GitHub CodeQL build options for Swift](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages#building-swift), [Swift.org LLVM sanitizer guide](https://www.swift.org/documentation/server/guides/llvm-sanitizers.html), and [Swift.org testing guide](https://www.swift.org/documentation/server/guides/testing.html).
