# Changelog

All notable changes to AstronomyKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Version tags include an `+upstream-X.Y.Z` suffix identifying the bundled Astronomy Engine C library version.

## [3.0.0+upstream-2.1.19] - 2026-09-09

### Added
- Polynomial planetary evaluation. For qualified segments from 1900 through 2100 TT, positions, heliocentric velocities, and heliocentric distances for Mercury through Neptune come from degree-12 Chebyshev fits of the full VSOP87B model instead of the summed series (local patch 9 in `MAINTAINING.md`). Mercury and Earth use eight-day segments, Saturn and Neptune sixteen days, and the other planets thirty-two days. 413 of 36,712 segments (Mercury 409, Venus 4) failed qualification and use the full series, as do dates outside coverage. Every shipping segment qualifies against the compensated full model at max(1e-12, |reference| × 1e-12) per component, with a maximum budget ratio of 0.41. Fresh-epoch position queries inside coverage run about 420× faster than the full series on an M1 Max. The tables add about 11.5 MB to the compiled library; nothing is downloaded or loaded at runtime. Public signatures and the supported date range are unchanged.
- Apparent geocentric ecliptic state. `CelestialBody.geocentricEclipticState(at:aberration:)`, `Sun.eclipticState(at:)`, and `Moon.eclipticState(at:)` return an `EclipticState`: longitude, latitude, and distance plus their rates, in the true ecliptic and equinox of date, from one call. Each mirrors one existing position function (`geocentricPosition(at:aberration:).toEcliptic()`, `Sun.position(at:)`, `Moon.ecliptic(at:)`) and its position fields are bit-identical to it. The C entry points are `Astronomy_GeoEclipticState`, `Astronomy_SunEclipticState`, and `Astronomy_MoonEclipticState` (local patch 12). A caller that differenced three positions to get a speed now makes one call: one light-time solution and one nutation evaluation instead of three. On an M1 Max in Release, one state call costs 1.15× to 1.6× one position call.
- Rates are the exact time derivative of the mirrored position with respect to Terrestrial Time days, holding Delta T fixed. For the Sun and planets they are analytic: implicit differentiation of the converged light-time fixed point (so the rate does not depend on how many iterations the position path ran), the observer's motion under the engine's backdated-observer aberration approximation, and the rotation rate of the true ecliptic and equinox of date from the precession polynomials, the 77-term IAU2000B series, and the obliquity. Pluto's velocity is the exact derivative of its interpolated position, which has small kinks at the state table's 146-day steps. The Moon has no analytic derivative in this engine; its rates are a central difference of the lunar series over ±43 seconds of TT, noisy at about 1e-7 degrees per day. Rates are per TT day: a consumer differencing `addingDays` (UT arithmetic) sees a ~3e-8 relative difference that this API does not model.
- Event searches that switch from differenced speeds to these rates will see station times move. Against 2,462 Mercury–Saturn stations of 1900–2100 located with the 0.0007-day central difference downstream consumers use, on these tables, no root moves more than 0.05 s (maximum 0.016 s, no bracket lost). Against a 0.02-day central difference, 528 move more than 0.05 s (maximum 0.106 s); that displacement is the wide stencil's truncation error, not rounding and not a model change. The largest distance from independently located station times remains 40.8 s against the 60 s gate.

### Changed
- **Breaking:** platform-native math replaces the vendored musl transcendentals introduced in 2.2.0, ending the cross-platform bit-identity contract. Outputs may differ in their last bits across OS, architecture, toolchain, and build configuration, and event searches can amplify those differences. The musl subset with FP contraction pinned off measured 2.2–2.5× slower on fresh-epoch positions and downstream scans, so it was dropped. Numerical regression tolerances in `ReproducibilityTests` replace the bit-exact goldens; the independent JPL Horizons and audit references and Linux CI are unchanged, and `#pragma STDC FP_CONTRACT OFF` stays in the vendored C.
- **Numerical change:** the VSOP87B series in `VsopCoords`, `VsopDeriv`, and `VsopHelioDistance` are accumulated with Neumaier compensated addition (same terms, same order; local patch 11). Plain addition lost low bits systematically, growing linearly with |t| to 4.45e-12 AU for Mercury, 1.5e-12 Venus, 1.2e-12 Earth, 1.7e-12 Mars, 1.2e-12 Jupiter, and 6e-13 to 8e-13 AU for the outer planets at the 1900 and 2100 edges. The compensated output matches an exactly summed evaluation of the same tables bit for bit. The 596-test suite, the 24,120 JPL positions, 2,462 stations, and 36 frozen events all pass; the largest historical station shift falls from 0.036 s to 0.005 s and the largest event shift from 0.073 s to 0.021 s. Full-series evaluation costs 6% to 13% more for Mercury through Mars and 30% to 39% more for Saturn through Neptune, on a path the polynomial tables make rare.
- The polynomial tables were refit against the compensated model with the screening limit tightened from 1e-11 to 2.5e-13 AU. The first archive (PR #36) disabled 10,069 of 34,418 segments because its 1e-12 qualification budget was measuring the reference's own summation error. Saturn moved from 32-day to 16-day segments; every body stays at degree 12. Against that archive on an M1 Max, day scans run 4.7 to 5.6× faster, the week scan 5.0×, and scoring 1.9×.
- `AstronomyConfig.ephemerisVersion` is `3.0.0+vsop87b-comp.poly-v2.iau2000b.utc-c72.native-libm`. Persisted numerical caches must key on that version and on the platform, architecture, OS, and toolchain. Review stored positions and event times after upgrading.

### Removed
- **Breaking:** the vendored musl math subset, its `ak_*` C symbols, and the `ak_math.h` header exported from `CLibAstronomy`. The Swift layer calls Foundation's `atan2`, `asin`, and `cos` directly. Code importing `CLibAstronomy` for the `ak_*` symbols must switch to the host libm.
- The CI `nm` guard that failed the build on host-libm references in the vendored C objects.
- The accuracy-investigation, native-math, VSOP-cache, and polynomial benchmark harnesses and their archived results under `Scripts/`, plus the `ACCURACY-INVESTIGATION.md` and `PRODUCTION-INTEGRATION.md` narratives and the paired downstream migration patch. Everything remains in git history at the merge commits of PRs #32 through #36. Only the generators that produce checked-in tables and the hardware-independent cache and polynomial probes are retained.

## [2.4.0+upstream-2.1.19] - 2026-09-07

### Changed
- Reuse exact planetary series results in a bounded per-thread cache for repeated position, state, and distance calculations (local patch 8 in `MAINTAINING.md`). Full model coefficients, summation order, civil time behavior, and numerical snapshots are unchanged.

## [2.3.0+upstream-2.1.19] - 2026-09-06

### Changed
- **Numerical compatibility break:** restore every retained VSOP87B term for Mercury through Neptune, including Earth, and all 77 IAU2000B nutation terms. Positions and analytic state derivatives use the same complete planetary tables. Public calculation signatures remain unchanged.
- **Time semantics:** `AstroTime(Date)`, calendar construction and `.now` interpret civil UTC using the bundled USNO 1961–2017 table, including pre-1972 linear offsets. Future dates hold the last announced leap-second offset. Earlier civil dates retain the historical UT1 proxy. Native calculations continue to use modeled UT1 and TT with the existing delta-T model.
- `.date` converts TT back to civil UTC for every time, including native search results. Foundation cannot represent leap seconds: positive gaps map to the following transition; historical overlaps choose the later civil occurrence. Numeric Codable and `init(ut:)` continue to represent UT1; `addingDays` and `addingHours` retain UT1 arithmetic. Existing serialized times can display different civil dates after upgrading.
- Consumers must invalidate version-dependent positions and review numerical snapshots. `AstronomyConfig.ephemerisVersion` identifies the model and civil-time table; this release ships it as `3.0.0-candidate.1+vsop87b.iau2000b.utc-c72`. Updated bit goldens are compatibility records, not independent accuracy references.
- `Package.swift` attaches the dev-only tooling after the package is constructed, so the target list no longer depends on the `.dev-tooling` sentinel.
- CI: the sanitizer workflow runs again, every action is pinned to a current commit, and every job has a timeout.

### Fixed
- Bound the native TT inverse so nonfinite or nonconvergent input returns an invalid time instead of looping forever.

### Qualification
- The integrated engine passed all 36 frozen event times from a downstream consumer within the 60-second gate (maximum 59.5 s), 2,462 independently located station roots over 1900–2100 (maximum 40.8 s), and 24,120 monthly positions against JPL Horizons; the full record is in git history at the merge of PR #32. No universal 60-second UTC accuracy claim is made for 1900–2100 or for unknown future leap seconds and Earth orientation.

## [2.2.0+upstream-2.1.19] - 2026-07-27

### Changed
- **Breaking:** ephemeris math is now deterministic across environments (issue #28). The transcendental functions the vendored C library relied on (`sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log10`, `pow`, `cbrt`, `hypot`) are now supplied by a vendored, `ak_`-prefixed subset of musl 1.2.5 with FP contraction pinned off, instead of the host libm. Positions are therefore bit-identical across macOS versions, Linux, and Swift toolchains, rather than differing in their last bits with each host libm. The one-time cost is a last-ULP shift in position values relative to every previous environment: downstream consumers with position-baselined tests must re-baseline once, after which the values are permanent across all operating systems. (`sqrt`, `fmod`, `floor`, `ceil`, and `fabs` remain the host's; they are IEEE-exact everywhere.) 3.0.0 returns to platform-native math.

### Added
- Bit-exact `ReproducibilityTests` (run in debug and release, on macOS and Linux CI) that assert transcendental and ephemeris outputs against frozen golden constants, plus a CI `nm` guard that fails the build if the vendored C objects reference any host-libm transcendental instead of the `ak_`-prefixed musl implementations.

## [2.1.0+upstream-2.1.19] - 2026-07-22

### Changed
- **Breaking:** Pluto positions for times more than ~100 years outside the tabulated range (roughly years 0000–4000) now throw `AstronomyError.badTime` instead of triggering an unbounded, ever-slower step-integration (a compute denial-of-service). This is a local patch to the vendored C library, guarded by `PLUTO_MAX_CRAWL_DAYS`.
- **Breaking:** `Chiron` calculations are now limited to years 1900–2150; times outside this range throw `AstronomyError.badTime`. Integration error grows with distance from the reference epochs, so far-off times were both slow and inaccurate.
- **Breaking:** removed the internal `CelestialBody.star1` slot. It exposed mutable global state in the vendored C library that only `FixedStar` was meant to configure; `FixedStar` now drives that slot directly under its own lock. `CelestialBody.allCases` again reflects every declared case (17), and `CelestialBody(rawValue: 101)` is `nil`.
- Fixed-star calculations now run concurrently across up to eight C star slots (`BODY_STAR1`…`BODY_STAR8`) instead of serializing every call on a single slot behind one lock. A star maps to a slot by a stable hash of its coordinates and each slot has its own mutex, so distinct stars compute in parallel; a slot is redefined only when it holds a different star, so repeated calls for the same star skip the redundant `Astronomy_DefineStar`. Colliding stars serialize on their shared slot.
- `RotationMatrix` now stores its 3×3 values inline as the C structure instead of a heap-allocated `[Double]`, eliminating a per-matrix allocation and the rebuild of the C representation on every use.
- `StateVector.init(_:)` constructs its `AstroTime` once and reuses it for the state and both vectors, rather than building three identical instances.

### Fixed
- `Astronomy_Constellation` lazily initialized its J2000→B1875 rotation matrix in function-local `static`s, so concurrent first calls raced. The vendored C library now guards that initialization with `pthread_once` (a local patch), and constellation lookups are safe to run concurrently from a cold start.
- `Seasons.forYear(_:)` and `RotationMatrix.pivot(axis:angle:)` trapped (crashed) on integer arguments outside the ranges the C layer accepts. They now throw `AstronomyError.invalidParameter` instead.
- Observers with non-finite coordinates, or a latitude outside -90...90, now throw `AstronomyError.invalidParameter` when used in a calculation rather than producing undefined results.

### Added
- Weekly (and on-demand) AddressSanitizer and UndefinedBehaviorSanitizer CI workflow, complementing the per-PR ThreadSanitizer job.

## [2.0.0+upstream-2.1.19] - 2026-07-08

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
- Concurrent Chiron position queries could corrupt one another. The gravity-simulation cache was a shared mutable global, so queries interleaving on different threads stepped the same integrator, a data race (reported by ThreadSanitizer) that also made light-travel corrections fail to converge. The reusable simulation is now scoped to each computation, so Chiron calculations hold no shared state and are safe to run concurrently.

### Added
- `AstronomyError` conforms to `LocalizedError`, so `localizedDescription` produces the descriptive message instead of a generic one.
- ThreadSanitizer and release-configuration test jobs in CI, plus a Delta T thread-safety stress test.
- CI now builds the library for each declared Apple platform (iOS, tvOS, watchOS) in addition to the macOS and Linux test jobs.
- `MAINTAINING.md` documenting how to update the vendored Astronomy Engine C library while preserving the local thread-safety patches.
- `.spi.yml` manifest so the Swift Package Index builds and hosts the DocC documentation.

## [1.1.0+upstream-2.1.19] - 2026-06-11

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
- **Breaking:** comprehensive naming audit. Abbreviated, terse, and underscore-separated identifiers were renamed to clear lowerCamelCase across the public API.
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

[3.0.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/2.4.0+upstream-2.1.19...3.0.0+upstream-2.1.19
[2.4.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/2.3.0+upstream-2.1.19...2.4.0+upstream-2.1.19
[2.3.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/2.2.0+upstream-2.1.19...2.3.0+upstream-2.1.19
[2.2.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/2.1.0+upstream-2.1.19...2.2.0+upstream-2.1.19
[2.1.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/2.0.0+upstream-2.1.19...2.1.0+upstream-2.1.19
[2.0.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/1.1.0+upstream-2.1.19...2.0.0+upstream-2.1.19
[1.1.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/1.0.0+upstream-2.1.19...1.1.0+upstream-2.1.19
[1.0.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.2+upstream-2.1.19...1.0.0+upstream-2.1.19
[0.2.2+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.1+upstream-2.1.19...0.2.2+upstream-2.1.19
[0.2.1+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.2.0+upstream-2.1.19...0.2.1+upstream-2.1.19
[0.2.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.1.1+upstream-2.1.19...0.2.0+upstream-2.1.19
[0.1.1+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/compare/0.1.0+upstream-2.1.19...0.1.1+upstream-2.1.19
[0.1.0+upstream-2.1.19]: https://github.com/heirloomlogic/AstronomyKit/releases/tag/0.1.0+upstream-2.1.19
