# Changelog

All notable changes to AstronomyKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Version tags include an `+upstream-X.Y.Z` suffix identifying the bundled Astronomy Engine C library version.

## [2.0.0+upstream-2.1.19]

### Changed
- **Breaking:** window-bounded searches now return `nil` instead of throwing when the event does not occur within the search window: `AstroSearch.find(from:to:toleranceSeconds:_:)`, `Sun.searchLongitude(_:after:limitDays:)`, and `Moon.searchPhase(_:after:limitDays:)` all return `AstroTime?`, matching the existing rise/set search convention. `AstronomyError.searchFailure` now indicates an internal solver failure.
- **Breaking:** `equatorial(at:from:equatorDate:aberration:)` on `CelestialBody` and `FixedStar` now defaults to a geocentric observer, matching its documentation. The old default was a surface point at 0°N 0°E, which silently added topocentric parallax (up to ~1° for the Moon). Pass an explicit observer for topocentric coordinates.
- **Breaking:** removed the deprecated `Observer.EquatorFrame` typealias; use `EquatorDate`.
- **Breaking:** `Moon.eclipticPosition(at:)` is renamed to `Moon.ecliptic(at:)` and now returns `Ecliptic` instead of `Spherical`, matching `Sun.position(at:)`, `Chiron.ecliptic(at:)`, and `FixedStar.ecliptic(at:)`. The latitude, longitude, and distance values are unchanged.
- `AstroSearch.find` and `AstroSearch.correctLightTravel` now each take a throwing closure (non-throwing closures still work unchanged), and abort the underlying C iteration immediately when the closure throws instead of continuing on placeholder values.

### Fixed
- Swapping the Delta T model while calculations run on other threads was a data race. The vendored C library now stores the Delta T function pointer as a C11 atomic (a local patch, like the existing Pluto cache mutex), and `AstronomyConfig.setDeltaTModel(_:)` is safe to call from any thread.
- The vendored C library's internal performance counters (`_CalcMoonCount`, `_AltitudeDiffCallCount`, `_FindAscentMaxRecursionDepth`) were incremented racily from concurrent Moon and rise/set calculations; they are now C11 atomics. The full test suite runs clean under ThreadSanitizer.
- `AstroTime(year:month:day:hour:minute:second:)` crashed when a component exceeded `Int32` range; components are now clamped.
- `Observer.description` crashed for non-finite or astronomically large heights.

### Added
- `AstronomyError` conforms to `LocalizedError`, so `localizedDescription` produces the descriptive message instead of a generic one.
- ThreadSanitizer and release-configuration test jobs in CI, plus a Delta T thread-safety stress test.
- CI now builds the library for each declared Apple platform (iOS, tvOS, watchOS) in addition to the macOS and Linux test jobs.
- `MAINTAINING.md` documenting how to update the vendored Astronomy Engine C library while preserving the local thread-safety patches.
- `.spi.yml` manifest so the Swift Package Index builds and hosts the DocC documentation.

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

[2.0.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/1.1.0+upstream-2.1.19...HEAD
[1.1.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/1.0.0+upstream-2.1.19...1.1.0+upstream-2.1.19
[1.0.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.2+upstream-2.1.19...1.0.0+upstream-2.1.19
[0.2.2+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.1+upstream-2.1.19...0.2.2+upstream-2.1.19
[0.2.1+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.0+upstream-2.1.19...0.2.1+upstream-2.1.19
[0.2.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.1.1+upstream-2.1.19...0.2.0+upstream-2.1.19
[0.1.1+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.1.0+upstream-2.1.19...0.1.1+upstream-2.1.19
[0.1.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/releases/tag/0.1.0+upstream-2.1.19
