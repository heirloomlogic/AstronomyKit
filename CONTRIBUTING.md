# Contributing to AstronomyKit

AstronomyKit is the open-source astronomy library powering [Fallow](https://heirloomlogic.com/fallow) and [Edict](https://heirloomlogic.com/edict) by [Heirloom Logic](https://heirloomlogic.com). Contributions that improve the library benefit everyone building with it.

## Reporting Bugs

Open a [bug report](https://github.com/heirloomlogic/AstronomyKit/issues/new?template=bug_report.md) with:

- The Swift and platform versions you are using
- A minimal code sample that reproduces the issue
- Expected vs. actual behavior

## Submitting Changes

1. Fork the repository and create a branch from `main`.
2. Make your changes.
3. Run `swift build` and resolve any swift-format lint warnings.
4. Run `swift test` and confirm all tests pass.
5. Open a pull request describing what you changed and why.

### Code Style

The project uses [swift-format](https://github.com/swiftlang/swift-format) via a build plugin. Linting runs automatically during builds, so `swift build` is enough to see all warnings. Resolve all lint warnings before submitting a PR.

Your local toolchain must match CI's Swift major.minor version; see [Toolchain Alignment](README.md#toolchain-alignment) in the README.

### Tests

New functionality should include tests. Bug fixes should include a test that would have caught the issue.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](.github/CODE_OF_CONDUCT.md). By participating, you agree to uphold it.

## Questions

If you have questions that aren't covered here, open an issue or email astronomykit@heirloomlogic.com.
