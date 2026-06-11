# Changelog

All notable changes to AstronomyKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Version tags include an `+upstream-X.Y.Z` suffix identifying the bundled Astronomy Engine C library version.

## [1.1.0+upstream-2.1.19]

### Added
- Provenance note in the vendored `astronomy.c` recording the upstream commit (`826e26ff3`) and local patches.

### Fixed
- `AstronomyConfig.reset()` could free the Pluto orbit cache while another thread was reading it (use-after-free). The vendored C library now holds the cache mutex across both the purge and the full segment read in `CalcPluto`.
- Chiron positions within one day of a reference epoch returned the epoch state verbatim (frozen position, wrong timestamp, and a discontinuity at the one-day boundary). Positions are now always simulated to the requested time.
- `Chiron.geoState(at:)` now derives Earth's velocity from `heliocentricState(at:)` instead of a finite difference, and documents that the state is geometric (not light-travel corrected).
- `Horizon.compassDirection` crashed for azimuths outside 0–360° (possible via the public initializer); the azimuth is now normalized first, and non-finite values no longer trap.
- `CelestialBody(name:)` is now case-insensitive as documented, and also accepts the Galilean moon names.
- `CelestialBody.name` returned an empty string for the Galilean moons; names are now provided for every case.
- `CelestialBody.allCases` no longer includes the internal `star1` slot used by `FixedStar`.
- `AstroTime.date` silently substituted the current time when calendar conversion failed; both `Date` conversions now use exact arithmetic with no fallback path.
- `Equatorial.rightAscensionFormatted` / `declinationFormatted` could print 60.0 seconds (e.g. "23h 59m 60.0s") instead of rolling over to the next minute.

### Changed
- Chiron queries now reuse a cached gravity simulation (with an integration-error budget) instead of re-integrating from a reference epoch on every call, making sequential queries and light-travel iteration substantially faster.
- `AstronomyConfig.setDeltaTModel(_:)` documents that it must be configured once at startup, before any other AstronomyKit call.
- `AstronomyConfig.reset()` documentation corrected: it only purges the Pluto cache; it never reset the Delta T model or star definitions.
- `Observer.EquatorFrame` is deprecated in favor of the equivalent `EquatorDate`; `Observer.vector(at:equator:)` and `state(at:equator:)` now take `EquatorDate`.
- CI hardening: the GitHub Pages deploy action is pinned to a commit SHA, and the test and lint workflows declare read-only permissions.

## [1.0.0+upstream-2.1.19] - 2026-06-05

### Added
- Conjunction and opposition search: `searchOpposition(after:)`, `searchSuperiorConjunction(after:)`, `searchRelativeLongitude(_:after:)`, and `pairLongitude(with:at:)` on `CelestialBody`.
- Sun ecliptic longitude search: `Sun.searchLongitude(_:after:limitDays:)`.
- Generic root-finding search: `AstroSearch.find(from:to:toleranceSeconds:_:)`.
- State vector methods: `barycentricState(at:)`, `heliocentricState(at:)`, and `earthMoonBaryState(at:)`.
- Vector conversions: `toSpherical()`, `toEquatorial()`, `toEcliptic()`, `angle(to:)`, and factory methods on `Vector3D` and `Spherical`.
- Ecliptic-of-date (ECT) rotation matrices.
- State vector rotation via `StateVector.rotated(by:)`.
- Fast Lagrange point calculation: `LagrangePoint.calculateFast(point:majorState:majorMass:minorState:minorMass:)`.
- Reverse observer lookup: `Observer.from(vector:equatorDate:)`.
- Direct hour angle getter: `CelestialBody.hourAngle(at:from:)`.
- Light-travel correction: `AstroSearch.correctLightTravel(at:_:)` and `CelestialBody.backdatedPosition(at:seenFrom:aberration:)`.
- AstronomyKit logo on the README header and DocC landing page.
- `CHANGELOG.md` and `SECURITY.md`.
- README section on toolchain alignment between development and CI.

### Fixed
- `Ecliptic` distance now correctly computes the vector magnitude (was storing the squared magnitude).
- Removed Git LFS so downstream SPM resolution succeeds (SPM does not run LFS smudge filters, so LFS-tracked images broke package resolution).

### Changed
- **Breaking:** comprehensive naming audit — abbreviated, terse, and underscore-separated identifiers renamed to clear, self-documenting lowerCamelCase across the public API.
- Raised minimum deployment targets to macOS 15 / iOS 18 / tvOS 18 / watchOS 11.
- Replaced `NSLock` with `Synchronization.Mutex` in `FixedStar` for Swift 6 concurrency.
- Switched swift-format tooling from SwiftFormatPlugin to Persnicket, and gated all dev-only tooling (Persnicket, swift-docc-plugin) behind a gitignored `.dev-tooling` sentinel so downstream consumers don't inherit build-tool plugins.
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

[1.1.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/1.0.0+upstream-2.1.19...HEAD
[1.0.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.2+upstream-2.1.19...1.0.0+upstream-2.1.19
[0.2.2+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.1+upstream-2.1.19...0.2.2+upstream-2.1.19
[0.2.1+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.0+upstream-2.1.19...0.2.1+upstream-2.1.19
[0.2.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.1.1+upstream-2.1.19...0.2.0+upstream-2.1.19
[0.1.1+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.1.0+upstream-2.1.19...0.1.1+upstream-2.1.19
[0.1.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/releases/tag/0.1.0+upstream-2.1.19
