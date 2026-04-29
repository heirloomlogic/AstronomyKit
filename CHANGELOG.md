# Changelog

All notable changes to AstronomyKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Version tags include an `+upstream-X.Y.Z` suffix identifying the bundled Astronomy Engine C library version.

## [Unreleased]

### Added
- Conjunction and opposition search: `searchOpposition(after:)`, `searchSuperiorConjunction(after:)`, `searchRelativeLongitude(_:after:)`, and `pairLongitude(with:at:)` on `CelestialBody`.
- Sun ecliptic longitude search: `Sun.searchLongitude(_:after:limitDays:)`.
- Generic root-finding search: `AstroSearch.find(from:to:toleranceSeconds:_:)`.
- State vector methods: `barycentricState(at:)`, `heliocentricState(at:)`, and `earthMoonBaryState(at:)`.
- Vector conversions: `toSpherical()`, `toEquatorial()`, `toEcliptic()`, `angle(to:)`, and factory methods on `Vector3D` and `Spherical`.
- Ecliptic-of-date (ECT) rotation matrices.
- State vector rotation via `StateVector.rotated(by:)`.
- `CHANGELOG.md` and `SECURITY.md`.
- README section on toolchain alignment between development and CI.

### Fixed
- `Ecliptic` distance now correctly computes the vector magnitude (was storing the squared magnitude).

### Changed
- Corrected accuracy claim from "sub-arcminute" to "±1 arcminute" to match Astronomy Engine's stated accuracy.
- Corrected model attribution from "derived from NASA JPL ephemeris data" to "based on VSOP87 and NOVAS C 3.1 models validated against JPL Horizons."
- Documentation now identifies Chiron and FixedStar as AstronomyKit additions beyond Astronomy Engine.
- Documentation workflow now publishes on version tags instead of every push to `main`.
- Test workflow now also runs on pushes to `main`, not only on pull requests.
- `Package.resolved` is no longer tracked in the repository.
- Swift-format lint warnings across sources and tests resolved.

## [0.2.2+upstream-2.1.19] - 2026-02-08

### Changed
- Switched lint tooling from SwiftLint to the Heirloom Logic SwiftFormatPlugin build tool plugin. Linting now runs automatically during `swift build`.

## [0.2.1+upstream-2.1.19] - 2026-01-08

### Fixed
- Resolved outstanding SwiftLint warnings.

### Changed
- README updates.

## [0.2.0+upstream-2.1.19] - 2026-01-06

### Added
- `FixedStar` type for user-defined stars specified by J2000 equatorial coordinates. Supports ecliptic longitude and horizon coordinate queries.
- `Chiron` gravity-simulated position (ecliptic, equatorial, and horizon coordinates) for 2060 Chiron, using pre-computed JPL Horizons state vectors.

## [0.1.1+upstream-2.1.19] - 2026-01-02

### Fixed
- Intermittent failures when running Pluto tests in parallel. `Chiron` and `Pluto` calculations now use a mutex to protect shared state in the underlying C library.

## [0.1.0+upstream-2.1.19] - 2026-01-02

Initial public release.

### Added
- Swift wrapper around Don Cross' [Astronomy Engine](https://github.com/cosinekitty/astronomy) C library (upstream 2.1.19).
- `CelestialBody` enum covering the Sun, Moon, planets, and Jupiter's Galilean moons.
- `AstroTime` with Foundation `Date` interop, UT/TT conversion, and arithmetic helpers.
- `Observer` geographic location type.
- `Equatorial`, `Ecliptic`, `Horizon`, and galactic coordinate types, with `RotationMatrix` transforms between all frames.
- `Moon` phase angle, phase names, quarters, illumination, and libration.
- `Seasons` equinox and solstice calculations.
- Rise, set, and culmination (`CelestialBody.riseTime`, `setTime`, `culmination`).
- Lunar and solar `Eclipse` prediction (including `GlobalSolarEclipse` and `LocalSolarEclipse`).
- `Apsis`, `Elongation`, `Transit`, `LunarNode`, `LagrangePoint`, `Constellation`, and `Illumination`.
- `GravitySimulation` N-body simulator.
- Tests validating positions against JPL Horizons ephemeris data to ±1 arcminute accuracy.
- DocC documentation and GitHub Actions workflows for tests and documentation publishing.
- Full `Sendable` conformance for Swift 6.

[Unreleased]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.2+upstream-2.1.19...HEAD
[0.2.2+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.1+upstream-2.1.19...0.2.2+upstream-2.1.19
[0.2.1+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.0+upstream-2.1.19...0.2.1+upstream-2.1.19
[0.2.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.1.1+upstream-2.1.19...0.2.0+upstream-2.1.19
[0.1.1+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.1.0+upstream-2.1.19...0.1.1+upstream-2.1.19
[0.1.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/releases/tag/0.1.0+upstream-2.1.19
