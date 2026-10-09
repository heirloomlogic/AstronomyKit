# Native public API integration

Issue [#96](https://github.com/heirloomlogic/AstronomyKit/issues/96) is a three-link integration chain. The geometry link is based on `068d62417e069d865f9f9e5e542fbe9a222086d7`; the geometric-body link is based on reviewed `0a66b1faea7abb2f3c87f0e4a2b97236c81354a9`. The shipping target still depends on `CLibAstronomy`; this link does not complete the cutover.

## Geometry operations

`RotationMatrix` stores nine native `Double` values and delegates construction, inverse, composition, pivots and frame transforms to `Engine.Rotation` and `Engine.FrameRotation`. Vector and state rotation retain the caller's `AstroTime`, including its stored TT and model. Matrix index order and throwing signatures stay unchanged.

Spherical/equatorial vector conversion, spherical/horizon vector construction, vector angles, horizon-vector conversion and refraction use native implementations. Nonthrowing zero-vector conversions still return NaN fields. Observer validation remains at the facade boundary; gravity, observer vectors and states use `Engine.Observers`. The observer inverse already used that implementation and now shares the measured-time conversion.

The final horizontal-coordinate conversion in `CelestialBody.horizon`, `FixedStar.horizon` and `Chiron.horizon` uses `Engine.Horizontal`. Body and Chiron apparent position calculations remain as before; fixed-star positions use the native immutable catalog implementation after link 2. This keeps their sidereal orientation consistent with the public horizon rotation matrices.

These paths inherit the existing native constants and formulas documented in `NATIVE_ENGINE.md`: the IAU 2006 J2000 obliquity, the IAU astronomical unit, and the complementary terms in apparent sidereal time. The complementary terms can change horizon orientation by about 2.65 milliarcseconds between 1950 and 2050. Spherical longitude that rounds up to 360 degrees wraps to zero. This link changes public numerical results where those native definitions differ from C; it does not introduce a new astronomical model or tolerance.

`AstroTime.coordinateTime` copies the stored UT/TT pair for operations that do not derive another epoch. Public results retain the original `AstroTime`. Time storage, process-default selection, time arithmetic and `AstroTime.siderealTime` remain C-backed in this link. This intermediate state does not establish complete public sidereal-time migration.

`Vector3D.toEcliptic()` also remains C-backed until the final time/position cutover. Its consumers promise bit-identical position fields between `geocentricEclipticState` and `geocentricPosition().toEcliptic()`, so the two paths migrate together. The existing exact assertions remain in place.

## Evidence

`NativeCoordinateFacadeTests` applies the existing SOFA angle and geodetic references to public frame rotations and observer results, preserves zero-vector/error/epoch behavior, and checks body/star horizontal conversions against the public rotation route. Existing `EclipticStateTests` and `ChironTests.HorizonTests` cover the two shared-path contracts that determine this link's boundary. Existing coordinate, observer, refraction and rotation tests remain unchanged. Published fixtures and tolerances are unchanged.

The release audit uses the latest published tag, `3.1.0+upstream-2.1.19`. Its symbol graph contains 539 public symbols; the first-link base contains 577. There are 42 added symbol identifiers and four removed identifiers, with no changed declarations among shared identifiers. The additions include the solar-altitude observation API and captured Delta T model API. The removed identifiers are the four old `AstroTime` initializers, replaced by versions with defaulted `deltaTModel` parameters. These differences precede this link and remain part of #96's final release acceptance; this audit does not approve them. Both integration candidates and their respective exact bases have identical public symbol declarations and relationships (577 symbols).

A public consumer probe encodes and decodes all eight Codable types with sorted JSON keys: `AstroTime`, `Observer`, `CelestialBody`, `MoonPhase`, `Visibility`, `ApsisKind`, `NodeKind` and `Seasons`. The released and candidate encoded results match byte for byte for those representative values, including all enum cases. This is sampled serialization evidence, not proof for every possible value.

The implementation PR records exact test commands, revisions, resource observations and hosted results. Local audit artifacts live in `.context/issue-96/link1/`, including the release/base symbol graphs, comparisons, Codable probe and results, source inventories, red/green logs and resource probe.

## Geometric bodies and auxiliary values

Link 2 routes heliocentric positions, heliocentric and barycentric states, distances, heliocentric ecliptic longitudes, Earth-Moon barycenter states, illumination, libration, Jupiter moons, rotation axes, constellations and fixed stars through the native engine. These paths read stored TT/UT and do not derive light-time epochs. Returned vectors and states retain the original public time, including unnamed C callbacks. Fixed stars now own immutable coordinates instead of sharing eight mutable C slots.

`AstronomyConfig.reset()` clears the native registry and the remaining C caches during this intermediate link. It preserves captured models, fixed-star definitions and owned gravity simulations. GravitySimulation owns a native simulation under its facade lock. The facade retains the original current and previous epochs, and the last requested time, so swaps and same-TT updates preserve the existing distinction between `time` and `currentTime()`. A failed update preserves all three. Public Chiron retains its UTC-assigned anchors, ICRF-as-EQJ convention and UT-nearest anchor selection; only its gravity dependency changes. The corrected anchor convention in `Engine.Chiron` is not adopted by this link.

The missing Lagrange and mass-product port is implemented in `Engine/Bodies/EngineLagrange.swift`, using existing native gravity constants and preserving the bounded Newton iteration, error ordering, degenerate-input checks and major-state epoch. Definition tests check rotating-frame equilibrium, equilateral L4/L5 geometry, and NASA's approximate 1.5-million-kilometer Sun-Earth L1/L2 distances. Existing public Lagrange edge tests remain unchanged. Issue [#90](https://github.com/heirloomlogic/AstronomyKit/issues/90) was reopened because its solver scope had not been implemented; independent review and its remaining acceptance evidence still govern closure.

The single Chiron C-bit-pattern distance fixture in `ReproducibilityTests` is replaced by exact repeatability across calls and public resets. At its 2026-07-24 epoch the native-gravity result is 18.25823887167392 AU, compared with the frozen C value 18.258238871645116 AU: a 4.309-meter difference. The published Horizons checks in `AuditValidationTests` and `ChironTests`, and the native source-based gravity checks, remain at their existing tolerances. The remaining C-pinning cases wait for the final dependent cutover.

These facades inherit the native numerical definitions already documented in `NATIVE_ENGINE.md`, including Saturn's physical-center trajectory, lunar DE441 coverage, native libration constants, IAU pole elements and constellation boundary rotation. They can change public numerical values. Published fixtures and tolerances remain unchanged.

## Final atomic cutover

Link 3 migrates apparent body/Sun/Moon positions, `Vector3D.toEcliptic()` and the exact ecliptic-state family together with events/searches and time/configuration. A trial partial migration exposed a mixed-model dependency: at TT −30381.25, the current C-derived UT reconstructs a native TT about 39.5 milliseconds later. Native light-time arithmetic combined with C time construction fails two existing Mercury finite-difference rate checks. Link 2 retains the original apparent paths and the unchanged checks; it neither alters the reference stencil nor widens their budgets.

The final link removes the remaining C adapters and shipping dependency, completes every named C-test disposition, and qualifies a clean consumer and the full platform matrix. The documented unnamed C Delta-T callback behavior and inherited released-API differences still need an evidenced final disposition. Only that link can complete #96 when all acceptance evidence passes.

The named cache suites `MoonCacheTests`, `NutationCacheTests` and `VsopCacheTests` were retired under #95 in favor of native cache checks. `DeltaTThreadSafetyTests` now uses the public model API. `BundledEphemerisTests`, `CivilTimeTests`, `EclipticStateTests`, `PolynomialTests` and `ReproducibilityTests` retain their current coverage pending the dependent migrations and recorded final disposition.

The owner-listed invalid-derived-time, Pluto apsis, altitude endpoint/pruning, lunar-eclipse start/tangency and non-central solar-eclipse regressions remain final public-cutover acceptance. Broader #92/#93 scientific qualification and the separately tracked public defects remain unresolved; geometry routing alone does not settle them.
