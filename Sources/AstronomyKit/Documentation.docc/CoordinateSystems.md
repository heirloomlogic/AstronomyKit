# Coordinate Systems

Transform positions between different astronomical coordinate systems.

## Overview

AstronomyKit supports multiple coordinate systems and provides rotation matrices for transforming between them. Understanding these systems is essential for precise astronomical work.

## Coordinate Systems

### Equatorial J2000 (EQJ)

The standard reference frame used by most star catalogs:
- Origin: Earth's center
- Fundamental plane: Earth's equator at J2000.0 epoch
- Primary direction: Vernal equinox at J2000.0

```swift
let eq = try CelestialBody.mars.equatorial(at: .now, equatorDate: .j2000)
print("RA: \(eq.rightAscension)h, Dec: \(eq.declination)°")
```

### Equatorial of Date (EQD)

Accounts for precession of Earth's axis:
- Same as EQJ but referenced to the current date

```swift
let eq = try CelestialBody.mars.equatorial(at: .now, equatorDate: .ofDate)
```

### Ecliptic (ECL)

Referenced to the plane of Earth's orbit:
- Fundamental plane: Ecliptic (Earth's orbital plane)
- Primary direction: Vernal equinox

```swift
let lon = try CelestialBody.jupiter.eclipticLongitude(at: .now)
print("Ecliptic longitude: \(lon)°")

// Full ecliptic position
let sunPos = try Sun.position(at: .now)
print("λ: \(sunPos.longitude)°, β: \(sunPos.latitude)°")
```

### Horizontal (HOR)

Local sky coordinates for an observer:
- Altitude: Height above the horizon
- Azimuth: Compass direction from north

```swift
let observer = Observer(latitude: 40.0, longitude: -74.0)
let hor = try CelestialBody.venus.horizon(at: .now, from: observer)
print("Alt: \(hor.altitude)°, Az: \(hor.azimuth)°")
```

### Galactic (GAL)

Referenced to the Milky Way:
- Fundamental plane: Galactic plane
- Primary direction: Galactic center

Available via rotation matrices (see below).

## Rotation Matrices

### Creating Rotation Matrices

```swift
// Equatorial J2000 to Ecliptic
let eqjToEcl = try RotationMatrix.equatorialJ2000ToEcliptic()

// Ecliptic to Equatorial J2000
let eclToEqj = try RotationMatrix.eclipticToEquatorialJ2000()

// Equatorial J2000 to Galactic
let eqjToGal = try RotationMatrix.equatorialJ2000ToGalactic()
```

### Time-Dependent Rotations

Some transformations require a time for precession/nutation:

```swift
// Equatorial J2000 to Equatorial of Date
let time = AstroTime.now
let eqjToEqd = try RotationMatrix.equatorialJ2000ToEquatorialOfDate(at: time)

// Equatorial to Horizontal (requires time and observer)
let observer = Observer.greenwich
let eqjToHor = try RotationMatrix.equatorialJ2000ToHorizon(at: time, from: observer)
```

### Applying Rotations

Transform a vector using a rotation matrix:

```swift
let position = try CelestialBody.mars.geoPosition(at: .now)
let rotation = try RotationMatrix.equatorialJ2000ToEcliptic()
let eclipticPosition = position.rotated(by: rotation)
```

### Matrix Operations

```swift
// Identity (no rotation)
let identity = RotationMatrix.identity

// Inverse (reverse rotation)
let forward = try RotationMatrix.equatorialJ2000ToEcliptic()
let reverse = forward.inverse

// Combine rotations
let combined = try forward.combined(with: anotherRotation)

// Pivot around an axis
let rotated = try RotationMatrix.pivot(axis: 2, angle: 45.0)  // 45° around Z
```

## Vector Types

### Vector3D

A 3D Cartesian position vector:

```swift
let pos = try CelestialBody.jupiter.geoPosition(at: .now)
print("X: \(pos.x) AU")
print("Y: \(pos.y) AU")
print("Z: \(pos.z) AU")
print("Magnitude: \(pos.magnitude) AU")

// Normalize to unit vector
let direction = pos.normalized
```

### StateVector

Position and velocity together:

```swift
let state = try observer.state(at: .now)
print("Position: \(state.position)")
print("Velocity: \(state.velocity)")  // AU/day
```

## Spherical Coordinates

Used for Moon's ecliptic position:

```swift
let moonPos = try Moon.eclipticPosition(at: .now)
print("Longitude: \(moonPos.longitude)°")
print("Latitude: \(moonPos.latitude)°")
print("Distance: \(moonPos.distance) AU")
```

## Atmospheric Effects

### Refraction

Atmospheric refraction bends light, affecting apparent altitude:

```swift
// Normal refraction correction (default)
let apparent = try body.horizon(at: .now, from: observer, refraction: .normal)

// No refraction (geometric position)
let geometric = try body.horizon(at: .now, from: observer, refraction: .none)

// JPL Horizons refraction model
let jpl = try body.horizon(at: .now, from: observer, refraction: .jplHorizons)
```

### Aberration

Light-time and stellar aberration affect apparent positions:

```swift
// With aberration correction (default) - what you actually see
let apparent = try body.geoPosition(at: .now, aberration: .corrected)

// Without correction - geometric position
let geometric = try body.geoPosition(at: .now, aberration: .none)
```

## Available Rotations

| From | To | Method |
|------|-----|--------|
| EQJ | ECL | `equatorialJ2000ToEcliptic()` |
| ECL | EQJ | `eclipticToEquatorialJ2000()` |
| EQJ | EQD | `equatorialJ2000ToEquatorialOfDate(at:)` |
| EQD | EQJ | `equatorialOfDateToEquatorialJ2000(at:)` |
| EQJ | HOR | `equatorialJ2000ToHorizon(at:from:)` |
| HOR | EQJ | `horizonToEquatorialJ2000(at:from:)` |
| EQJ | GAL | `equatorialJ2000ToGalactic()` |
| GAL | EQJ | `galacticToEquatorialJ2000()` |
| ECL | HOR | `eclipticToHorizon(at:from:)` |
| HOR | ECL | `horizonToEcliptic(at:from:)` |
| EQD | ECL | `equatorialOfDateToEcliptic(at:)` |
| ECL | EQD | `eclipticToEquatorialOfDate(at:)` |
| HOR | EQD | `horizonToEquatorialOfDate(at:from:)` |
