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
5. Run `swift test` and confirm all tests pass.
6. Open a pull request describing what you changed and why.

### Code Style

The project uses [swift-format](https://github.com/swiftlang/swift-format) via a build plugin. The plugin is **dev-gated**: it (and the rest of the dev tooling) only resolves when a gitignored `.dev-tooling` sentinel is present, so consumers who depend on AstronomyKit never inherit it. Run `touch .dev-tooling` once before your first build to enable it; linting then runs automatically during builds, so `swift build` is enough to see all warnings. Resolve all lint warnings before submitting a PR.

If you already built *before* creating the sentinel, SwiftPM has cached the manifest in consumer mode (it keys the cache on the manifest's text, which doesn't change when the sentinel does). Clear that one cache layer with `swift package purge-cache` followed by `swift package resolve` — note that `swift package reset` and Xcode's "Reset Package Caches" do **not** clear it; `purge-cache` is the specific verb.

Your local toolchain must match CI's Swift major.minor version; see [Toolchain Alignment](README.md#toolchain-alignment) in the README.

### Tests

New functionality should include tests. Bug fixes should include a test that would have caught the issue.

Run the whole suite with `swift test`. Suites run in parallel in one process, and Swift Testing's `.serialized` trait only orders tests inside a single suite, so a test that changes process-wide state such as the Delta T model can make unrelated suites fail intermittently. The Delta T thread-safety test avoids this: its writers swap between two functions that return identical results, so ThreadSanitizer still sees a real pointer swap while other suites get the same values. A time created during a swap can carry the stand-in and report a `nil` `deltaTModel`, so check values, not `deltaTModel`, for times made under the process default. The thread-safety test's own checks never assume which function is the default, because another suite can construct a time or reset the model between any two of its statements.

### Fuzzing the C bridge

`Fuzzing/` holds a libFuzzer harness for the vendored C library, outside the Swift package. If you change how the Swift layer passes numbers into the C code, or change the C code itself, replay the seed corpus under AddressSanitizer and UndefinedBehaviorSanitizer with `sh Fuzzing/build.sh replay && .build/fuzz/replay-bridge Fuzzing/corpus`. That works with Apple clang; fuzzing for new inputs needs clang from LLVM. The Fuzz workflow replays the corpus and fuzzes on Linux for pull requests that touch the C library. See [Fuzzing/README.md](Fuzzing/README.md).

### Updating the vendored C library

AstronomyKit vendors the Astronomy Engine C library (`Sources/CLibAstronomy/`) with local patches: thread safety, the full VSOP87B and IAU2000B tables, compensated summation, polynomial evaluation, the analytic ecliptic state, guards against non-finite or extreme inputs, checks that reject non-finite results, an accepted time range for the ephemeris models, and a Delta T function captured in each time value. If you need to update it from upstream, follow [MAINTAINING.md](MAINTAINING.md) so the patches are preserved and the accuracy tests still pass.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](.github/CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Questions

If you have questions that aren't covered here, open an issue or email astronomykit@heirloomlogic.com.
