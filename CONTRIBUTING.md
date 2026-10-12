# Contributing to AstronomyKit

AstronomyKit is the open-source astronomy library behind [Fallow](https://heirloomlogic.com/fallow) and [Edict](https://heirloomlogic.com/edict) by [Heirloom Logic](https://heirloomlogic.com).

## Reporting Bugs

Open a [bug report](https://github.com/heirloomlogic/AstronomyKit/issues/new?template=bug_report.md) with:

- The Swift and platform versions you are using
- A minimal code sample that reproduces the issue
- Expected vs. actual behavior

## Submitting Changes

1. Fork the repository and create a branch from `main`.
2. Run `touch .dev-tooling` once, **before your first build**, to enable the swift-format build plugin (see [Code Style](#code-style)).
3. Make your changes.
4. Run `swift build` and resolve any swift-format lint warnings.
5. Run `swift test --no-parallel -c release` and confirm all tests pass.
6. Open a pull request describing what you changed and why.

### Code Style

The project uses [swift-format](https://github.com/swiftlang/swift-format) via a build plugin. The plugin is **dev-gated**: it (and the rest of the dev tooling) only resolves when a gitignored `.dev-tooling` sentinel is present, so consumers who depend on AstronomyKit never inherit it. Run `touch .dev-tooling` once before your first build to enable it; linting then runs automatically during builds, so `swift build` is enough to see all warnings. Resolve all lint warnings before submitting a PR.

If you already built *before* creating the sentinel, SwiftPM has cached the manifest in consumer mode (it keys the cache on the manifest's text, which doesn't change when the sentinel does). Clear that one cache layer with `swift package purge-cache` followed by `swift package resolve` — note that `swift package reset` and Xcode's "Reset Package Caches" do **not** clear it; `purge-cache` is the specific verb.

Your local toolchain must match CI's Swift major.minor version; see [Toolchain Alignment](README.md#toolchain-alignment) in the README.

### Tests

New functionality should include tests. Bug fixes should include a test that would have caught the issue.

For routine development, run the full numerical suite with `swift test --no-parallel -c release`. Run focused Debug regressions with `python3 Scripts/run-pr-tests.py`; add `--sanitize=thread` or `--sanitize=address` for the same selection under a sanitizer. On Linux, set `LSAN_OPTIONS=suppressions=$PWD/.github/lsan-suppressions.txt` when running ASan. `python3 Scripts/run-pr-tests.py --list` shows and validates the selected tests. The explicit suite list covers native input safety, cache behavior, concurrent callers, and model capture; adding a test to a selected suite includes it automatically. Missing suites fail discovery rather than silently shrinking coverage.

PR CI runs the full Release suite on macOS and Linux, focused Debug on both platforms, focused Linux ASan/TSan, fast fixture/provenance checks, and platform builds/runtime smoke tests. The feedback target is 20 minutes after runner startup, with a maximum of 25 minutes per routine test job. Queue time is separate. Do not raise that ceiling to absorb an expanding suite; profile the new cost and move exhaustive qualification work to the workflow below. Release uses the same scientific assertions and tolerances as Debug.

The **Scientific qualification** workflow retains full Debug coverage on macOS and Linux, full Linux ASan/TSan, and native numerical remeasurement. It runs weekly on the default branch and on demand using **Actions → Scientific qualification → Run workflow**, selecting the candidate branch. For an unmerged scientific feature, apply the `full-qualification` PR label; the workflow runs against the exact PR head and reruns when that head changes. Each job records its verified commit SHA in its summary. Manual dispatch becomes available after this workflow reaches the default branch; the label trigger works on this PR immediately.

Scientific feature acceptance and releases require successful qualification of the candidate commit in addition to routine PR checks. A weekly run of another commit does not qualify a candidate. Full qualification can take hours and is not part of ordinary PR feedback. The workflow preserves all existing commands, including ASan's isolated timed suites and process-default mutators; splitting scheduling does not establish that an unfinished qualification has passed.

To reproduce exhaustive Debug locally, run `swift test --no-parallel`. For full ASan, run `Scripts/test-with-isolated-default-model.sh --sanitize=address` with the Linux leak suppression above; for full TSan, run `swift test --no-parallel --sanitize=thread`. Serial suite execution protects process-wide state such as the Delta T default; the concurrency regressions still launch simultaneous callers inside individual tests.

### Fuzzing the C bridge

`Fuzzing/` holds a libFuzzer harness for the vendored C library, outside the Swift package. If you change how the Swift layer passes numbers into the C code, or change the C code itself, replay the seed corpus under AddressSanitizer and UndefinedBehaviorSanitizer with `sh Fuzzing/build.sh replay && .build/fuzz/replay-bridge Fuzzing/corpus`. That works with Apple clang; fuzzing for new inputs needs clang from LLVM. The Fuzz workflow replays the corpus and fuzzes on Linux for pull requests that touch the C library. See [Fuzzing/README.md](Fuzzing/README.md).

### Changing the vendored C library

AstronomyKit vendors the Astronomy Engine C library (`Sources/CLibAstronomy/`) with local patches: thread safety, the full VSOP87B and IAU2000B tables, compensated summation, polynomial evaluation, the analytic ecliptic state, guards against non-finite or extreme inputs, checks that reject non-finite results, an accepted time range for the ephemeris models, and a Delta T function captured in each time value. The project does not sync with upstream Astronomy Engine. When you change the C library, keep the patches listed in [MAINTAINING.md](MAINTAINING.md) intact and the accuracy tests passing.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](.github/CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Questions

If you have questions that aren't covered here, open an issue or email astronomykit@heirloomlogic.com.
