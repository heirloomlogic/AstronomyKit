# Native public API integration

Issue [#96](https://github.com/heirloomlogic/AstronomyKit/issues/96) is a three-link integration chain. The geometry link is based on `068d62417e069d865f9f9e5e542fbe9a222086d7`; the geometric-body link on reviewed `0a66b1faea7abb2f3c87f0e4a2b97236c81354a9`; the final cutover on `976da4bbcbdb2f38d484be46be2bd098b252fe23`. After the third link the shipping target has no dependency on `CLibAstronomy`.

## Geometry operations

`RotationMatrix` stores nine native `Double` values and delegates construction, inverse, composition, pivots and frame transforms to `Engine.Rotation` and `Engine.FrameRotation`. Vector and state rotation retain the caller's `AstroTime`, including its stored TT and model. Matrix index order and throwing signatures stay unchanged.

Spherical/equatorial vector conversion, spherical/horizon vector construction, vector angles, horizon-vector conversion and refraction use native implementations. Nonthrowing zero-vector conversions still return NaN fields. Observer validation remains at the facade boundary; gravity, observer vectors and states use `Engine.Observers`. The observer inverse already used that implementation and now shares the measured-time conversion.

The final horizontal-coordinate conversion in `CelestialBody.horizon`, `FixedStar.horizon` and `Chiron.horizon` uses `Engine.Horizontal`. Body and Chiron apparent position calculations remain as before; fixed-star positions use the native immutable catalog implementation after link 2. This keeps their sidereal orientation consistent with the public horizon rotation matrices.

These paths inherit the existing native constants and formulas documented in `NATIVE_ENGINE.md`: the IAU 2006 J2000 obliquity, the IAU astronomical unit, and the complementary terms in apparent sidereal time. The complementary terms can change horizon orientation by about 2.65 milliarcseconds between 1950 and 2050. Spherical longitude that rounds up to 360 degrees wraps to zero. This link changes public numerical results where those native definitions differ from C; it does not introduce a new astronomical model or tolerance.

In this link `AstroTime.coordinateTime` copied the stored UT/TT pair for operations that did not derive another epoch, and public results retained the original `AstroTime`. Time storage, process-default selection, time arithmetic, `AstroTime.siderealTime` and `Vector3D.toEcliptic()` stayed on C until the third link, because the consumers of `toEcliptic()` promise bit-identical position fields with `geocentricEclipticState`, so the two paths had to move together.

## Evidence

`NativeCoordinateFacadeTests` applies the existing SOFA angle and geodetic references to public frame rotations and observer results, preserves zero-vector/error/epoch behavior, and checks body/star horizontal conversions against the public rotation route. Existing `EclipticStateTests` and `ChironTests.HorizonTests` cover the two shared-path contracts that determine this link's boundary. Existing coordinate, observer, refraction and rotation tests remain unchanged. Published fixtures and tolerances are unchanged.

The release audit uses the latest published tag, `3.1.0+upstream-2.1.19`. Its symbol graph contains 539 public symbols; the first-link base contains 577. There are 42 added symbol identifiers and four removed identifiers, with no changed declarations among shared identifiers. The additions include the solar-altitude observation API and captured Delta T model API. The removed identifiers are the four old `AstroTime` initializers, replaced by versions with defaulted `deltaTModel` parameters. These differences precede this link and remain part of #96's final release acceptance; this audit does not approve them. Both integration candidates and their respective exact bases have identical public symbol declarations and relationships (577 symbols).

A public consumer probe encodes and decodes all eight Codable types with sorted JSON keys: `AstroTime`, `Observer`, `CelestialBody`, `MoonPhase`, `Visibility`, `ApsisKind`, `NodeKind` and `Seasons`. The released and candidate encoded results match byte for byte for those representative values, including all enum cases. This is sampled serialization evidence, not proof for every possible value.

The implementation PR records exact test commands, revisions, resource observations and hosted results. Local audit artifacts live in `.context/issue-96/link1/`, including the release/base symbol graphs, comparisons, Codable probe and results, source inventories, red/green logs and resource probe.

## Geometric bodies and auxiliary values

Link 2 routes heliocentric positions, heliocentric and barycentric states, distances, heliocentric ecliptic longitudes, Earth-Moon barycenter states, illumination, libration, Jupiter moons, rotation axes, constellations and fixed stars through the native engine. These paths read stored TT/UT and do not derive light-time epochs. Returned vectors and states retain the original public time, including unnamed C callbacks. Fixed stars now own immutable coordinates instead of sharing eight mutable C slots.

`AstronomyConfig.reset()` cleared the native registry and the remaining C caches during this intermediate link. It preserves captured models, fixed-star definitions and owned gravity simulations. GravitySimulation owns a native simulation under its facade lock. The facade retains the original current and previous epochs, and the last requested time, so swaps and same-TT updates preserve the existing distinction between `time` and `currentTime()`. A failed update preserves all three. Public Chiron retains its UTC-assigned anchors, ICRF-as-EQJ convention and UT-nearest anchor selection; only its gravity dependency changes. The corrected anchor convention in `Engine.Chiron` is not adopted by this link.

The missing Lagrange and mass-product port is implemented in `Engine/Bodies/EngineLagrange.swift`, using existing native gravity constants and preserving the bounded Newton iteration, error ordering, degenerate-input checks and major-state epoch. Definition tests check rotating-frame equilibrium, equilateral L4/L5 geometry, and NASA's approximate 1.5-million-kilometer Sun-Earth L1/L2 distances. Existing public Lagrange edge tests remain unchanged. Issue [#90](https://github.com/heirloomlogic/AstronomyKit/issues/90) was reopened because its solver scope had not been implemented; independent review and its remaining acceptance evidence still govern closure.

The single Chiron C-bit-pattern distance fixture in `ReproducibilityTests` is replaced by exact repeatability across calls and public resets. At its 2026-07-24 epoch the native-gravity result is 18.25823887167392 AU, compared with the frozen C value 18.258238871645116 AU: a 4.309-meter difference. The published Horizons checks in `AuditValidationTests` and `ChironTests`, and the native source-based gravity checks, remain at their existing tolerances. The remaining C-pinning cases wait for the final dependent cutover.

These facades inherit the native numerical definitions already documented in `NATIVE_ENGINE.md`, including Saturn's physical-center trajectory, lunar DE441 coverage, native libration constants, IAU pole elements and constellation boundary rotation. They can change public numerical values. Published fixtures and tolerances remain unchanged.

## Final cutover

The third link moves everything that was left: apparent geocentric positions and states, `Vector3D.toEcliptic()` and the exact ecliptic-state family, `Sun.position` and `Sun.eclipticState`, `Moon.geocentricPosition`, `ecliptic`, `eclipticState` and `geoState`, `equatorial`, `horizon`, `angleFromSun`, `pairLongitude`, `elongation`, `backdatedPosition`, every event search (rise/set, altitude, hour angle, seasons, solar longitude, lunar phase, quarter, node and apsis, planetary apsis, relative longitude, maximum elongation, peak magnitude), lunar, global and local solar eclipses, transits, `AstroSearch.find` and `correctLightTravel`, `AstroTime` construction and arithmetic, `siderealTime`, the Delta T functions and the process default. `AstroTime` stores an `Engine.Time`. The `AstronomyKit` target declares no dependency; `Sources/CLibAstronomy` stays in the tree until #97 and #99 remove it, and nothing links it.

The trial partial migration recorded above failed two Mercury rate checks because a C-derived time pair reconstructed a native TT about 39.5 ms later. Moving time and positions together removes the mixed-model dependency; the Mercury checks run unchanged.

### Public differences

The public API now returns the engine's values where the engine differs from the C engine. Each difference is recorded in `NATIVE_ENGINE.md` under its module; the ones a caller can see are:

- Delta T: Espenak-Meeus takes NASA's decimal year, about 0.02 s from the C value in 2026 and 2.1 s at −1999. The JPL Horizons approximation holds Delta T at the same date as before.
- Calendar: `AstroTime(year:month:day:)` normalizes every month with floor division, so months past 14 are no longer one or two days late (#164).
- Invalid times: a time derived from an invalid time stays invalid, keeping its UT with a NaN TT and no model, as the owner chose on #168. `Astronomy_SetDeltaTFunction` and unnamed Delta T callbacks are gone, as the owner chose on #96; `deltaTModel` is `nil` only for an invalid time.
- Orientation: IAU 2006/2000A nutation, apparent sidereal time with the complementary terms, the IAU 2006 obliquity and the published au and light-day (#166). The light-day limit in `AstroSearch.correctLightTravel` is 173.144 632 674 240 33 AU.
- Moon and Pluto: the Moon uses DE440 from 1900 through 2130 and complete binary64 DE441 coefficients elsewhere in the accepted range. Pluto uses DE440 and PLU060 for its center from 1800 through 2199 and the DE441 system barycenter elsewhere in the accepted range. Rates are analytic throughout. Before the cutover, the C path used the lunar series and the integrated Pluto model outside the bundled interval.
- Searches: the altitude scan clips its last step to the declared window and prunes with the full half-span slope bound; the lunar eclipse search rechecks the full Moon before its start; non-central solar eclipses keep their annular or total kind with a surface witness; the Neptune/Pluto apsis refinement returns the midpoint of its final span; the transit peak minimizes angular separation. The owner-listed public defects on #92 and #93 end here, and `NativeCutoverTests` keeps each case on the public API.
- Rise/set: the solar limb is 696,000 km, and the South Pole row 2,923 passes its 70.8 s allowance (#124).

### Test dispositions

Every test that imported `CLibAstronomy` or pinned C output has a recorded disposition in `NATIVE_ENGINE.md`: `BundledEphemerisTests` retired with its Horizons event regression and Moon identity moved to `MoonStateIdentityTests`; `CivilTimeTests` and `DeltaTThreadSafetyTests` kept on the engine; `EclipticStateTests` kept for its public identities and rates with its direct C checks retired to the engine suites; `PolynomialTests` moved onto the public API; `ReproducibilityTests` reduced to repeatability, its C bit patterns retired rather than re-recorded; `NativePositionBridgeTests` and the unnamed-callback case of `ObserverVectorTests` retired with the callbacks; `EngineContractTests` now covers the whole `Sources/AstronomyKit` tree and the manifest. No published fixture or tolerance changed.

### Released API

The released-API differences recorded above are unchanged by this link: 42 added identifiers and the four `AstroTime` initializers replaced by versions with a defaulted `deltaTModel` parameter. Their release disposition is the owner's; the cutover PR lists them as an open decision. The base and candidate public symbol graphs are compared on the PR.
