# Native public API integration

Issue [#96](https://github.com/heirloomlogic/AstronomyKit/issues/96) is a three-link integration chain. This records the first link, based on `068d62417e069d865f9f9e5e542fbe9a222086d7`. The shipping target still depends on `CLibAstronomy`; this link does not complete the cutover.

## Geometry operations

`RotationMatrix` stores nine native `Double` values and delegates construction, inverse, composition, pivots and frame transforms to `Engine.Rotation` and `Engine.FrameRotation`. Vector and state rotation retain the caller's `AstroTime`, including its stored TT and model. Matrix index order and throwing signatures stay unchanged.

Spherical/equatorial vector conversion, spherical/horizon vector construction, vector angles, horizon-vector conversion and refraction use native implementations. Nonthrowing zero-vector conversions still return NaN fields. Observer validation remains at the facade boundary; gravity, observer vectors and states use `Engine.Observers`. The observer inverse already used that implementation and now shares the measured-time conversion.

The final horizontal-coordinate conversion in `CelestialBody.horizon`, `FixedStar.horizon` and `Chiron.horizon` uses `Engine.Horizontal`. Their upstream position calculations remain as before. This keeps their sidereal orientation consistent with the public horizon rotation matrices.

These paths inherit the existing native constants and formulas documented in `NATIVE_ENGINE.md`: the IAU 2006 J2000 obliquity, the IAU astronomical unit, and the complementary terms in apparent sidereal time. The complementary terms can change horizon orientation by about 2.65 milliarcseconds between 1950 and 2050. Spherical longitude that rounds up to 360 degrees wraps to zero. This link changes public numerical results where those native definitions differ from C; it does not introduce a new astronomical model or tolerance.

`AstroTime.coordinateTime` copies the stored UT/TT pair for operations that do not derive another epoch. Public results retain the original `AstroTime`. Time storage, process-default selection, time arithmetic and `AstroTime.siderealTime` remain C-backed in this link. This intermediate state does not establish complete public sidereal-time migration.

`Vector3D.toEcliptic()` also remains C-backed until the position/state link. Its consumers promise bit-identical position fields between `geocentricEclipticState` and `geocentricPosition().toEcliptic()`, so the two paths migrate together. The existing exact assertions remain in place.

## Evidence

`NativeCoordinateFacadeTests` applies the existing SOFA angle and geodetic references to public frame rotations and observer results, preserves zero-vector/error/epoch behavior, and checks body/star horizontal conversions against the public rotation route. Existing `EclipticStateTests` and `ChironTests.HorizonTests` cover the two shared-path contracts that determine this link's boundary. Existing coordinate, observer, refraction and rotation tests remain unchanged. Published fixtures and tolerances are unchanged.

The release audit uses the latest published tag, `3.1.0+upstream-2.1.19`. Its symbol graph contains 539 public symbols; the first-link base contains 577. There are 42 added symbol identifiers and four removed identifiers, with no changed declarations among shared identifiers. The additions include the solar-altitude observation API and captured Delta T model API. The removed identifiers are the four old `AstroTime` initializers, replaced by versions with defaulted `deltaTModel` parameters. These differences precede this link and remain part of #96's final release acceptance; this audit does not approve them. The first-link candidate and its exact base have identical public symbol declarations and relationships.

A public consumer probe encodes and decodes all eight Codable types with sorted JSON keys: `AstroTime`, `Observer`, `CelestialBody`, `MoonPhase`, `Visibility`, `ApsisKind`, `NodeKind` and `Seasons`. The released and candidate encoded results match byte for byte for those representative values, including all enum cases. This is sampled serialization evidence, not proof for every possible value.

The implementation PR records exact test commands, revisions, resource observations and hosted results. Local audit artifacts live in `.context/issue-96/link1/`, including the release/base symbol graphs, comparisons, Codable probe and results, source inventories, red/green logs and resource probe.

## Remaining links

1. Link 2 migrates body/position/state, fixed-star/constellation, lunar value, Jupiter moons, rotation axes, Lagrange, Chiron and gravity facades. It moves `toEcliptic()` with the bit-identical position/state paths.
2. Link 3 migrates events/searches and time/configuration, removes the remaining C adapters and shipping dependency, completes the named C-test dispositions, and qualifies a clean consumer plus the full platform matrix. Only that link can complete #96 when its acceptance evidence is satisfied.

The named cache suites `MoonCacheTests`, `NutationCacheTests` and `VsopCacheTests` were retired under #95 in favor of native cache checks. `DeltaTThreadSafetyTests` now uses the public model API. `BundledEphemerisTests`, `CivilTimeTests`, `EclipticStateTests`, `PolynomialTests` and `ReproducibilityTests` retain their current coverage pending the dependent migrations and recorded final disposition.

The owner-listed invalid-derived-time, Pluto apsis, altitude endpoint/pruning, lunar-eclipse start/tangency and non-central solar-eclipse regressions remain final public-cutover acceptance. Broader #92/#93 scientific qualification and the separately tracked public defects remain unresolved; geometry routing alone does not settle them.
