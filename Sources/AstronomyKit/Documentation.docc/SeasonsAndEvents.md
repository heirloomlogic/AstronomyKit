# Seasons and Events

Calculate equinoxes, solstices, planetary apsides, elongations, and transits.

## Overview

AstronomyKit provides calculations for seasonal events (equinoxes and solstices), planetary orbital events (apsides), elongation and visibility, and rare transits of Mercury and Venus.

## Equinoxes and Solstices

### Get All Seasons for a Year

```swift
let seasons = try Seasons.forYear(2025)

print("🌸 Spring: \(seasons.marchEquinox)")
print("☀️ Summer: \(seasons.juneSolstice)")
print("🍂 Autumn: \(seasons.septemberEquinox)")
print("❄️ Winter: \(seasons.decemberSolstice)")
```

### Iterate Over Events

```swift
let seasons = try Seasons.forYear(2025)

for (name, time) in seasons.allEvents {
    print("\(name): \(time)")
}
```

## Planetary Apsides

Apsides are the closest (perihelion) and farthest (aphelion) points in a planet's orbit around the Sun.

### Find Next Planetary Apsis

```swift
let apsis = try CelestialBody.mars.searchApsis(after: .now)
print("\(apsis.kind.solarName) at \(apsis.time)")
print("Distance: \(apsis.distanceAU) AU")
```

### All Apsides in a Range

```swift
let apsides = try CelestialBody.earth.apsides(
    from: AstroTime(year: 2025, month: 1, day: 1),
    to: AstroTime(year: 2030, month: 1, day: 1)
)

for apsis in apsides {
    print("\(apsis.kind.solarName): \(apsis.time)")
}
```

## Elongation and Visibility

Elongation is the angular separation between a planet and the Sun. This determines when planets are best visible.

### Current Elongation

```swift
let elong = try CelestialBody.venus.elongation(at: .now)
print("Venus is \(elong.angle)° from the Sun")
print("Visibility: \(elong.visibility.name) star")

if elong.visibility == .evening {
    print("Look for Venus after sunset")
} else {
    print("Look for Venus before sunrise")
}
```

### Maximum Elongation

Find when a planet reaches greatest separation from the Sun:

```swift
let maxElong = try CelestialBody.mercury.searchMaxElongation(after: .now)
print("Mercury max elongation: \(maxElong.angle)°")
print("Date: \(maxElong.time)")
print("\(maxElong.visibility.name) star")
```

This is especially useful for Mercury and Venus, which are never far from the Sun.

## Illumination and Magnitude

Calculate the visual brightness and illumination of planets.

### Current Illumination

```swift
let illum = try CelestialBody.venus.illumination(at: .now)
print("Magnitude: \(illum.magnitude)")
print("Phase: \(Int(illum.phaseFraction * 100))% illuminated")
print("Distance from Sun: \(illum.helioDistance) AU")
```

### Saturn's Rings

For Saturn, illumination includes ring tilt:

```swift
let saturn = try CelestialBody.saturn.illumination(at: .now)
print("Ring tilt: \(saturn.ringTilt)°")
```

### Peak Magnitude

Find when a planet reaches maximum brightness:

```swift
let peak = try CelestialBody.venus.searchPeakMagnitude(after: .now)
print("Venus brightest at \(peak.time)")
print("Magnitude: \(peak.magnitude)")
```

## Planetary Transits

Transits occur when Mercury or Venus passes between Earth and the Sun.

> Note: Transits are rare events. Mercury transits occur about 13 times per century, while Venus transits occur in pairs separated by over a century.

### Find Next Transit

```swift
let transit = try Transit.search(body: .mercury, after: .now)
print("Transit date: \(transit.peak)")
print("Duration: \(transit.duration / 60) minutes")
```

### Transit Timing

```swift
print("Start (first contact): \(transit.start)")
print("Peak (mid-transit): \(transit.peak)")
print("End (last contact): \(transit.finish)")
print("Minimum separation: \(transit.separation) arcmin")
```

### All Transits in a Range

```swift
// Find all Mercury transits in the next 50 years
let transits = try Transit.transits(
    body: .mercury,
    from: .now,
    to: .now.addingDays(365 * 50)
)

for transit in transits {
    print("\(transit.body.name) transit: \(transit.peak)")
}
```

## Angular Separation

Calculate the angle between a body and the Sun:

```swift
let angle = try CelestialBody.jupiter.angleFromSun(at: .now)
print("Jupiter is \(angle)° from the Sun")

// Opposition occurs when angle ≈ 180°
if angle > 170 {
    print("Jupiter is near opposition!")
}
```

## Conjunctions and Oppositions

Search for when a planet reaches a specific angular relationship with the Sun:

```swift
// Find the next Mars opposition (closest to Earth)
let opposition = try CelestialBody.mars.searchOpposition(after: .now)
print("Mars opposition: \(opposition.date)")

// Find the next Jupiter superior conjunction (behind the Sun)
let conjunction = try CelestialBody.jupiter.searchSuperiorConjunction(after: .now)
print("Jupiter conjunction: \(conjunction.date)")

// Measure the relative ecliptic longitude between two bodies
let angle = try CelestialBody.venus.pairLongitude(with: .mars, at: .now)
print("Venus-Mars separation: \(angle)°")

// Search for an arbitrary relative longitude from the Sun
let result = try CelestialBody.saturn.searchRelativeLongitude(90, after: .now)
```

The relative longitude convention measures the heliocentric angle between the planet
and Earth. At 0° the planet and Earth are on the same side of the Sun (opposition for
outer planets). At 180° the planet is on the far side of the Sun (superior conjunction).
