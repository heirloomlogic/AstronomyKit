# Celestial Positions

Calculate the positions of celestial bodies in various coordinate systems.

## Overview

AstronomyKit can calculate positions for the Sun, Moon, planets, Jupiter's moons, and fixed stars. Positions can be expressed in multiple coordinate systems.

## Celestial Bodies

### Available Bodies

```swift
// Major bodies
let sun = CelestialBody.sun
let moon = CelestialBody.moon
let mars = CelestialBody.mars

// All planets (Mercury through Neptune)
for planet in CelestialBody.planets {
    print(planet.name)
}

// Jupiter's Galilean moons
for moon in CelestialBody.galileanMoons {
    print(moon.name)  // Io, Europa, Ganymede, Callisto
}
```

### Body Properties

```swift
let mars = CelestialBody.mars

print(mars.name)           // "Mars"
print(mars.orbitalPeriod)  // ~686 days
print(mars.massProduct)    // Mass × G in AU³/day²
print(mars.isPlanet)       // true
print(mars.isNakedEyeVisible)  // true
```

### Looking Up Bodies by Name

```swift
if let body = CelestialBody(name: "Jupiter") {
    print("Found: \(body)")
}
```

## Horizon Coordinates

Where does a body appear in your local sky?

```swift
let observer = Observer(latitude: 40.7128, longitude: -74.0060)
let mars = try CelestialBody.mars.horizon(at: .now, from: observer)

print("Altitude: \(mars.altitude)°")     // Height above horizon
print("Azimuth: \(mars.azimuth)°")       // Compass bearing
print("Direction: \(mars.compassDirection)")  // N, NE, E, SE, etc.

if mars.isAboveHorizon {
    print("Mars is visible!")
}
```

## Equatorial Coordinates

Right ascension and declination on the celestial sphere:

```swift
let eq = try CelestialBody.saturn.equatorial(at: .now)

print("RA: \(eq.rightAscension) hours")
print("Dec: \(eq.declination)°")
print("Distance: \(eq.distance) AU")

// Formatted output
print(eq.rightAscensionFormatted)   // "02h 15m 30.2s"
print(eq.declinationFormatted)      // "+12° 34' 56.7""
```

### Equator Date Options

Choose the reference equinox:

```swift
// J2000 coordinates (default) - standard reference epoch
let j2000 = try body.equatorial(at: .now, equatorDate: .j2000)

// Coordinates of the observation date - accounts for precession
let ofDate = try body.equatorial(at: .now, equatorDate: .ofDate)
```

## Ecliptic Coordinates

Position relative to the ecliptic plane:

```swift
let longitude = try CelestialBody.venus.eclipticLongitude(at: .now)
print("Venus ecliptic longitude: \(longitude)°")

// Sun's full ecliptic position
let sunPos = try Sun.position(at: .now)
print("Sun: λ=\(sunPos.longitude)°, β=\(sunPos.latitude)°")
```

## Position Vectors

Cartesian coordinates in 3D space:

```swift
// Geocentric (from Earth's center)
let geo = try CelestialBody.jupiter.geoPosition(at: .now)
print("Distance from Earth: \(geo.magnitude) AU")

// Heliocentric (from Sun's center)
let helio = try CelestialBody.mars.helioPosition(at: .now)
print("Distance from Sun: \(helio.magnitude) AU")
```

## Distance Calculations

```swift
// Distance from Sun
let auFromSun = try CelestialBody.mars.distanceFromSun(at: .now)
print("Mars is \(auFromSun) AU from the Sun")

// Angular separation from Sun
let angle = try CelestialBody.venus.angleFromSun(at: .now)
print("Venus is \(angle)° from the Sun")
```

## Constellation Identification

Find which constellation contains a body:

```swift
let constellation = try CelestialBody.mars.constellation(at: .now)
print("\(constellation.symbol) - \(constellation.name)")
// Output: "Tau - Taurus"

// Or from raw coordinates
let orion = try Constellation.find(ra: 5.9195, dec: 7.4071)
print(orion.name)  // "Orion"
```

## Fixed Stars

Define and track fixed stars by their J2000 catalog coordinates using ``FixedStar``:

```swift
// Define Algol (Beta Persei)
let algol = FixedStar(
    name: "Algol",
    ra: 3.136148,      // J2000 RA in hours
    dec: 40.9556,      // J2000 Dec in degrees
    distance: 92.95    // Light-years
)

// Get ecliptic longitude
let longitude = try algol.eclipticLongitude(at: .now)

// Get position in local sky
let observer = Observer(latitude: 40.7, longitude: -74.0)
let horizon = try algol.horizon(at: .now, from: observer)
```

J2000 coordinates can be found from star catalogs like SIMBAD, Hipparcos, or the Yale Bright Star Catalog.

## Aberration Correction

Control light-time and aberration corrections:

```swift
// With correction (default) - apparent position
let apparent = try body.geoPosition(at: .now, aberration: .corrected)

// Without correction - geometric position
let geometric = try body.geoPosition(at: .now, aberration: .none)
```

## Refraction Correction

Atmospheric refraction affects horizon coordinates:

```swift
// Normal refraction (default)
let normal = try body.horizon(at: .now, from: observer, refraction: .normal)

// No refraction
let geometric = try body.horizon(at: .now, from: observer, refraction: .none)

// JPL Horizons model
let jpl = try body.horizon(at: .now, from: observer, refraction: .jplHorizons)
```
