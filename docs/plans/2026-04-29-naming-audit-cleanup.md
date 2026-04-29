# Naming Audit Cleanup

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename every poorly-named public API symbol, parameter, and internal variable in AstronomyKit to clear, self-documenting lowerCamelCase names.

**Architecture:** Pure mechanical renames. No behavior changes. Each task is one rename (or a small batch of closely-related renames), followed by build + test to catch anything the text search missed. Tasks are ordered smallest-blast-radius first.

**Tech Stack:** Swift 6, swift-format lint, Swift Testing

---

### Task 1: Local variable renames (internal only)

**Files:**
- Modify: `Sources/AstronomyKit/Coordinates.swift` (line 53)
- Modify: `Sources/AstronomyKit/CelestialBody.swift` (lines 124-125)
- Modify: `Sources/AstronomyKit/Chiron.swift` (lines 198-204)

**Step 1: Rename `m` to `length` in Coordinates.swift**

In the `normalized` computed property (~line 53):
```swift
// BEFORE
let m = magnitude
guard m > 0 else { return self }
return Vector3D(x: x / m, y: y / m, z: z / m, time: time)

// AFTER
let length = magnitude
guard length > 0 else { return self }
return Vector3D(x: x / length, y: y / length, z: z / length, time: time)
```

**Step 2: Rename `mp` to `massProduct` in CelestialBody.swift**

In the `massProduct` computed property (~line 124):
```swift
// BEFORE
let mp = Astronomy_MassProduct(raw)
return mp > 0 ? mp : nil

// AFTER
let massProduct = Astronomy_MassProduct(raw)
return massProduct > 0 ? massProduct : nil
```

**Step 3: Rename `dt` to `timeStep` in Chiron.swift**

In the `geoState(at:)` method (~line 198):
```swift
// BEFORE
let dt = 1.0 / 86_400.0
... time.addingDays(-dt) ...
... time.addingDays(dt) ...
... / (2 * dt) ...

// AFTER
let timeStep = 1.0 / 86_400.0
... time.addingDays(-timeStep) ...
... time.addingDays(timeStep) ...
... / (2 * timeStep) ...
```

**Step 4: Build and test**

```bash
swift build 2>&1
swift test 2>&1
```
Expected: all pass, no compile errors.

**Step 5: Commit**

```bash
git add Sources/AstronomyKit/Coordinates.swift Sources/AstronomyKit/CelestialBody.swift Sources/AstronomyKit/Chiron.swift
git commit -m "Rename terse local variables: m, mp, dt"
```

---

### Task 2: Rename `var t = time.raw` to `var rawTime = time.raw` everywhere

This pattern appears ~21 times. Every occurrence follows the same shape: `var t = time.raw` on one line, then `&t` passed to a C function on the next.

**Files:**
- Modify: `Sources/AstronomyKit/Rotation.swift` (16 occurrences)
- Modify: `Sources/AstronomyKit/Position.swift` (2 occurrences, lines 70, 91)
- Modify: `Sources/AstronomyKit/Observer.swift` (2 occurrences, lines 138, 154)
- Modify: `Sources/AstronomyKit/RotationAxis.swift` (1 occurrence, line 82)
- Modify: `Sources/AstronomyKit/RiseSet.swift` (1 occurrence, line 219)
- Modify: `Sources/AstronomyKit/Chiron.swift` (1 occurrence, line 357)

**Step 1: In every file above, replace all occurrences**

```swift
// BEFORE
var t = time.raw
... &t ...

// AFTER
var rawTime = time.raw
... &rawTime ...
```

Use find-and-replace within each file. Be careful: only rename the *local variable* `t`, not any other use of `t` (like struct field access or other identifiers).

In each file, `var t = time.raw` is always immediately followed by a C function call using `&t`. Replace both `var t` and `&t` together.

**Step 2: Build and test**

```bash
swift build 2>&1
swift test 2>&1
```

**Step 3: Commit**

```bash
git add Sources/AstronomyKit/Rotation.swift Sources/AstronomyKit/Position.swift Sources/AstronomyKit/Observer.swift Sources/AstronomyKit/RotationAxis.swift Sources/AstronomyKit/RiseSet.swift Sources/AstronomyKit/Chiron.swift
git commit -m "Rename var t to var rawTime in C interop call sites"
```

---

### Task 3: Rename Search.swift internal params `t1`/`t2` to `startTime`/`endTime`

**Files:**
- Modify: `Sources/AstronomyKit/Search.swift` (lines 54-55 doc, 60-62 signature, 68 usage)

**Step 1: Rename parameters and their doc comments**

```swift
// BEFORE (doc)
///   - t1: The start of the search window.
///   - t2: The end of the search window.

// AFTER (doc)
///   - startTime: The start of the search window.
///   - endTime: The end of the search window.

// BEFORE (signature)
public static func find(
    from t1: AstroTime,
    to t2: AstroTime,

// AFTER (signature)
public static func find(
    from startTime: AstroTime,
    to endTime: AstroTime,

// BEFORE (body, line 68)
Astronomy_Search(searchTrampoline, ptr, t1.raw, t2.raw, toleranceSeconds)

// AFTER (body)
Astronomy_Search(searchTrampoline, ptr, startTime.raw, endTime.raw, toleranceSeconds)
```

External labels are `from:` and `to:` so call sites are unaffected.

**Step 2: Build and test**

```bash
swift build 2>&1
swift test 2>&1
```

**Step 3: Commit**

```bash
git add Sources/AstronomyKit/Search.swift
git commit -m "Rename Search.find internal params t1/t2 to startTime/endTime"
```

---

### Task 4: Rename `emb` to `earthMoonBarycenter` and `ssb` to `solarSystemBarycenter`

**Files:**
- Modify: `Sources/AstronomyKit/CelestialBody.swift` (lines 64, 67)
- Modify: `Sources/AstronomyKit/GravitySimulation.swift` (line 32, doc comment)

**Step 1: Rename enum cases**

```swift
// BEFORE
case emb = 11
case ssb = 12

// AFTER
case earthMoonBarycenter = 11
case solarSystemBarycenter = 12
```

**Step 2: Update doc example in GravitySimulation.swift**

```swift
// BEFORE
/// let state = try sim.state(of: .ssb)

// AFTER
/// let state = try sim.state(of: .solarSystemBarycenter)
```

**Step 3: Build and test**

```bash
swift build 2>&1
swift test 2>&1
```

**Step 4: Commit**

```bash
git add Sources/AstronomyKit/CelestialBody.swift Sources/AstronomyKit/GravitySimulation.swift
git commit -m "Rename emb/ssb enum cases to earthMoonBarycenter/solarSystemBarycenter"
```

---

### Task 5: Rename Constellation `ra1875`/`dec1875` and `find(ra:dec:)`

**Files:**
- Modify: `Sources/AstronomyKit/Constellation.swift` (lines 15, 22, 33, 36, 45, 46, 72, 75, 98)
- Modify: `Tests/AstronomyKitTests/ConstellationTests.swift` (lines 17, 26, 34, 37, 38, 53, 54, 61, 62, 70)
- Modify: `Sources/AstronomyKit/Documentation.docc/CelestialPositions.md` (line 144)

**Step 1: Rename properties in Constellation.swift**

```swift
// BEFORE
public let ra1875: Double
public let dec1875: Double
...
self.ra1875 = raw.ra_1875
self.dec1875 = raw.dec_1875

// AFTER
public let rightAscension1875: Double
public let declination1875: Double
...
self.rightAscension1875 = raw.ra_1875
self.declination1875 = raw.dec_1875
```

**Step 2: Rename `find(ra:dec:)` to `find(rightAscension:declination:)`**

In Constellation.swift, update the function signature, doc comments, and doc examples:

```swift
// BEFORE
/// The 'find(ra:dec:)' function accepts J2000 coordinates
/// let constellation = try Constellation.find(ra: 5.9195, dec: 7.4071)
/// let constellation = try Constellation.find(ra: 2.5303, dec: 89.2641)
public static func find(ra: Double, dec: Double) throws -> Constellation {
...
return try Constellation.find(ra: eq.rightAscension, dec: eq.declination)

// AFTER
/// The 'find(rightAscension:declination:)' function accepts J2000 coordinates
/// let constellation = try Constellation.find(rightAscension: 5.9195, declination: 7.4071)
/// let constellation = try Constellation.find(rightAscension: 2.5303, declination: 89.2641)
public static func find(rightAscension: Double, declination: Double) throws -> Constellation {
...
return try Constellation.find(rightAscension: eq.rightAscension, declination: eq.declination)
```

Also update the body of `find` where `ra` and `dec` are used (the C call).

**Step 3: Update all call sites in ConstellationTests.swift**

Replace every `Constellation.find(ra:` with `Constellation.find(rightAscension:` and `dec:` with `declination:`. Also update `.ra1875` to `.rightAscension1875` and `.dec1875` to `.declination1875`.

**Step 4: Update CelestialPositions.md**

```swift
// BEFORE
let orion = try Constellation.find(ra: 5.9195, dec: 7.4071)

// AFTER
let orion = try Constellation.find(rightAscension: 5.9195, declination: 7.4071)
```

**Step 5: Build and test**

```bash
swift build 2>&1
swift test 2>&1
```

**Step 6: Commit**

```bash
git add Sources/AstronomyKit/Constellation.swift Tests/AstronomyKitTests/ConstellationTests.swift Sources/AstronomyKit/Documentation.docc/CelestialPositions.md
git commit -m "Rename Constellation ra/dec to rightAscension/declination"
```

---

### Task 6: Rename FixedStar init params `ra:`/`dec:` to `rightAscension:`/`declination:`

**Files:**
- Modify: `Sources/AstronomyKit/FixedStar.swift` (line 73, plus doc examples ~line 25)
- Modify: `Tests/AstronomyKitTests/FixedStarTests.swift` (lines 20, 42, 43, 230, 231, 246, 247, 265)
- Modify: `Sources/AstronomyKit/Documentation.docc/CelestialPositions.md` (lines 156-157)
- Modify: `Sources/AstronomyKit/Documentation.docc/AdvancedFeatures.md` (lines 182-183, 190-191)
- Modify: `README.md` (lines 159-160)

**Step 1: Update init signature and body in FixedStar.swift**

```swift
// BEFORE
public init(name: String, ra: Double, dec: Double, distance: Double) {
    self.rightAscension = ra
    self.declination = dec

// AFTER
public init(name: String, rightAscension: Double, declination: Double, distance: Double) {
    self.rightAscension = rightAscension
    self.declination = declination
```

Also update the doc example in the same file.

**Step 2: Update all call sites in FixedStarTests.swift**

Replace `ra:` with `rightAscension:` and `dec:` with `declination:` at every `FixedStar(` call.

**Step 3: Update documentation files**

In CelestialPositions.md, AdvancedFeatures.md, and README.md, replace `ra:` with `rightAscension:` and `dec:` with `declination:` in all `FixedStar(` examples.

**Step 4: Build and test**

```bash
swift build 2>&1
swift test 2>&1
```

**Step 5: Commit**

```bash
git add Sources/AstronomyKit/FixedStar.swift Tests/AstronomyKitTests/FixedStarTests.swift Sources/AstronomyKit/Documentation.docc/CelestialPositions.md Sources/AstronomyKit/Documentation.docc/AdvancedFeatures.md README.md
git commit -m "Rename FixedStar init params ra/dec to rightAscension/declination"
```

---

### Task 7: Rename `deltaTEspenakMeeus(ut:)` and `deltaTJplHorizons(ut:)` parameter

**Files:**
- Modify: `Sources/AstronomyKit/AstronomyKit.swift` (lines 66, 75)
- Modify: `Sources/AstronomyKit/Documentation.docc/TimeAndObservers.md` (line 85)

**Step 1: Rename the `ut` parameter to `universalTime`**

```swift
// BEFORE
public static func deltaTEspenakMeeus(ut: Double) -> Double {
    Astronomy_DeltaT_EspenakMeeus(ut)
}
public static func deltaTJplHorizons(ut: Double) -> Double {
    Astronomy_DeltaT_JplHorizons(ut)
}

// AFTER
public static func deltaTEspenakMeeus(universalTime: Double) -> Double {
    Astronomy_DeltaT_EspenakMeeus(universalTime)
}
public static func deltaTJplHorizons(universalTime: Double) -> Double {
    Astronomy_DeltaT_JplHorizons(universalTime)
}
```

**Step 2: Update TimeAndObservers.md doc example**

```swift
// BEFORE
let deltaT = AstronomyConfig.deltaTEspenakMeeus(ut: 0)  // Seconds at J2000

// AFTER
let deltaT = AstronomyConfig.deltaTEspenakMeeus(universalTime: 0)  // Seconds at J2000
```

**Step 3: Build and test**

```bash
swift build 2>&1
swift test 2>&1
```

**Step 4: Commit**

```bash
git add Sources/AstronomyKit/AstronomyKit.swift Sources/AstronomyKit/Documentation.docc/TimeAndObservers.md
git commit -m "Rename deltaT parameter ut to universalTime"
```

---

### Task 8: Rename AstroTime `.ut` to `.universalTime` and `.tt` to `.terrestrialTime`

This has the second-widest blast radius. Many test files and two source files reference `.ut` and `.tt`.

**Files:**
- Modify: `Sources/AstronomyKit/Time.swift` (lines 43, 49, 189, 196)
- Modify: `Sources/AstronomyKit/Chiron.swift` (lines 375, 382)
- Modify: `Sources/AstronomyKit/Documentation.docc/TimeAndObservers.md` (lines 65-66)
- Modify: `Tests/AstronomyKitTests/SeasonsTests.swift` (lines 24-27, 181)
- Modify: `Tests/AstronomyKitTests/RelativeLongitudeTests.swift` (line 105)
- Modify: `Tests/AstronomyKitTests/AstroTimeTests.swift` (lines 80, 106, 115, 138, 160, 173, 176, 301, 336)
- Modify: `Tests/AstronomyKitTests/RiseSetTests.swift` (line 48)
- Modify: `Tests/AstronomyKitTests/SearchTests.swift` (lines 19, 29, 39, 43, 61, 73)
- Modify: `Tests/AstronomyKitTests/AuditValidationTests.swift` (line 316)

**Step 1: Rename properties in Time.swift**

```swift
// BEFORE
public var ut: Double { raw.ut }
public var tt: Double { raw.tt }

// AFTER
public var universalTime: Double { raw.ut }
public var terrestrialTime: Double { raw.tt }
```

Also update the `Equatable` and `Comparable` conformances:
```swift
// BEFORE
lhs.ut == rhs.ut
lhs.ut < rhs.ut

// AFTER
lhs.universalTime == rhs.universalTime
lhs.universalTime < rhs.universalTime
```

**Step 2: Update Chiron.swift**

Replace `.time.ut` with `.time.universalTime` on lines 375 and 382.

**Step 3: Update TimeAndObservers.md**

```swift
// BEFORE
print("UT: \(time.ut)")  // Days since J2000 noon (UTC)
print("TT: \(time.tt)")  // Days since J2000 noon (TT)

// AFTER
print("UT: \(time.universalTime)")  // Days since J2000 noon (UTC)
print("TT: \(time.terrestrialTime)")  // Days since J2000 noon (TT)
```

**Step 4: Update all test files**

Replace every `.ut` with `.universalTime` and `.tt` with `.terrestrialTime` across all test files listed above. Be careful to match exact patterns (e.g. `.ut` not `ut` in other contexts).

**Step 5: Build and test**

```bash
swift build 2>&1
swift test 2>&1
```

**Step 6: Commit**

```bash
git add Sources/AstronomyKit/Time.swift Sources/AstronomyKit/Chiron.swift Sources/AstronomyKit/Documentation.docc/TimeAndObservers.md Tests/AstronomyKitTests/SeasonsTests.swift Tests/AstronomyKitTests/RelativeLongitudeTests.swift Tests/AstronomyKitTests/AstroTimeTests.swift Tests/AstronomyKitTests/RiseSetTests.swift Tests/AstronomyKitTests/SearchTests.swift Tests/AstronomyKitTests/AuditValidationTests.swift
git commit -m "Rename AstroTime ut/tt to universalTime/terrestrialTime"
```

---

### Task 9: Rename `geoPosition` to `geocentricPosition` and `helioPosition` to `heliocentricPosition`

Largest blast radius. Touches nearly every source and test file.

**Files:**
- Modify: `Sources/AstronomyKit/Position.swift` (lines 22, 37 — definitions)
- Modify: `Sources/AstronomyKit/MoonPhase.swift` (line 245 — definition)
- Modify: `Sources/AstronomyKit/Chiron.swift` (lines 43, 161, 174, 175, 178, 195, 199, 200, 231, 256, 288, 315)
- Modify: `Sources/AstronomyKit/Documentation.docc/CoordinateSystems.md` (lines 101, 130, 198, 201)
- Modify: `Sources/AstronomyKit/Documentation.docc/CelestialPositions.md` (lines 114, 118, 177, 180)
- Modify: `Tests/AstronomyKitTests/ChironTests.swift` (lines 21, 34, 85, 99)
- Modify: `Tests/AstronomyKitTests/PositionTests.swift` (lines 22, 31, 32, 40, 49, 50, 62, 75, 87, 96, 97, 106)
- Modify: `Tests/AstronomyKitTests/AstronomyErrorTests.swift` (line 202)
- Modify: `Tests/AstronomyKitTests/StateVectorExtensionTests.swift` (lines 32, 69, 80, 90, 130, 145)
- Modify: `Tests/AstronomyKitTests/LightTravelTests.swift` (lines 18, 34)

**Step 1: Rename definitions in Position.swift**

```swift
// BEFORE
public func geoPosition(
public func helioPosition(at time: AstroTime) throws -> Vector3D {

// AFTER
public func geocentricPosition(
public func heliocentricPosition(at time: AstroTime) throws -> Vector3D {
```

**Step 2: Rename definitions in MoonPhase.swift and Chiron.swift**

Same pattern — rename `geoPosition` to `geocentricPosition` and `helioPosition` to `heliocentricPosition` in function names and all internal call sites.

**Step 3: Update all test files**

Replace `geoPosition` with `geocentricPosition` and `helioPosition` with `heliocentricPosition` at every call site in the test files listed above.

**Step 4: Fix LightTravelTests.swift `try!`**

While touching this file, also fix the remaining `try!` (line 18):
```swift
// BEFORE
try! CelestialBody.mars.heliocentricPosition(at: time)

// AFTER
try CelestialBody.mars.heliocentricPosition(at: time)
```

This works because we added the throwing overload of `correctLightTravel` in a previous commit.

**Step 5: Update documentation files**

Replace `geoPosition` with `geocentricPosition` and `helioPosition` with `heliocentricPosition` in CoordinateSystems.md and CelestialPositions.md.

**Step 6: Build and test**

```bash
swift build 2>&1
swift test 2>&1
```

**Step 7: Commit**

```bash
git add Sources/AstronomyKit/Position.swift Sources/AstronomyKit/MoonPhase.swift Sources/AstronomyKit/Chiron.swift Sources/AstronomyKit/Documentation.docc/CoordinateSystems.md Sources/AstronomyKit/Documentation.docc/CelestialPositions.md Tests/AstronomyKitTests/ChironTests.swift Tests/AstronomyKitTests/PositionTests.swift Tests/AstronomyKitTests/AstronomyErrorTests.swift Tests/AstronomyKitTests/StateVectorExtensionTests.swift Tests/AstronomyKitTests/LightTravelTests.swift
git commit -m "Rename geoPosition/helioPosition to geocentricPosition/heliocentricPosition"
```

---

## Verification

After all tasks, run a final clean build and full test suite:

```bash
swift build 2>&1
swift test 2>&1
```

Then run lint to confirm no new violations:
```bash
swift-format lint --recursive Sources/
```

All 528+ tests should pass. No compile errors. No lint warnings.

## Summary of all renames

| Before | After | Scope |
|--------|-------|-------|
| `m` (Coordinates.swift) | `length` | local |
| `mp` (CelestialBody.swift) | `massProduct` | local |
| `dt` (Chiron.swift) | `timeStep` | local |
| `var t = time.raw` (21 sites) | `var rawTime = time.raw` | local |
| `t1`/`t2` (Search.swift) | `startTime`/`endTime` | internal param |
| `.emb` | `.earthMoonBarycenter` | public enum case |
| `.ssb` | `.solarSystemBarycenter` | public enum case |
| `ra1875`/`dec1875` | `rightAscension1875`/`declination1875` | public property |
| `find(ra:dec:)` | `find(rightAscension:declination:)` | public method |
| `FixedStar(ra:dec:)` | `FixedStar(rightAscension:declination:)` | public init |
| `deltaTX(ut:)` | `deltaTX(universalTime:)` | public param |
| `.ut`/`.tt` | `.universalTime`/`.terrestrialTime` | public property |
| `geoPosition` | `geocentricPosition` | public method |
| `helioPosition` | `heliocentricPosition` | public method |
