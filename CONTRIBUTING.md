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
5. Run `swift test --no-parallel` and confirm all tests pass (see [Tests](#tests) for why the flag matters).
6. Open a pull request describing what you changed and why.

### Code Style

The project uses [swift-format](https://github.com/swiftlang/swift-format) via a build plugin. The plugin is **dev-gated**: it (and the rest of the dev tooling) only resolves when a gitignored `.dev-tooling` sentinel is present, so consumers who depend on AstronomyKit never inherit it. Run `touch .dev-tooling` once before your first build to enable it; linting then runs automatically during builds, so `swift build` is enough to see all warnings. Resolve all lint warnings before submitting a PR.

If you already built *before* creating the sentinel, SwiftPM has cached the manifest in consumer mode (it keys the cache on the manifest's text, which doesn't change when the sentinel does). Clear that one cache layer with `swift package purge-cache` followed by `swift package resolve` — note that `swift package reset` and Xcode's "Reset Package Caches" do **not** clear it; `purge-cache` is the specific verb.

Your local toolchain must match CI's Swift major.minor version; see [Toolchain Alignment](README.md#toolchain-alignment) in the README.

### Tests

New functionality should include tests. Bug fixes should include a test that would have caught the issue.

Run the whole suite with `swift test --no-parallel`. The Delta T thread-safety test swaps the process-global model on purpose, and Swift Testing's `.serialized` trait only orders tests inside that suite, so a parallel run can see unrelated suites fail intermittently. CI runs every job with the flag.

### Updating the vendored C library

AstronomyKit vendors the Astronomy Engine C library (`Sources/CLibAstronomy/`) with local patches: thread safety, the full VSOP87B and IAU2000B tables, compensated summation, polynomial evaluation, and the analytic ecliptic state. If you need to update it from upstream, follow [MAINTAINING.md](MAINTAINING.md) so the patches are preserved and the accuracy tests still pass.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](.github/CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Questions

If you have questions that aren't covered here, open an issue or email astronomykit@heirloomlogic.com.
