# Eclipses

Predict lunar and solar eclipses with detailed timing information.

## Overview

AstronomyKit can search for and predict lunar eclipses, global solar eclipses, and local solar eclipse visibility for specific observer locations.

## Lunar Eclipses

### Finding the Next Lunar Eclipse

```swift
let eclipse = try Eclipse.searchLunar(after: .now)
print("\(eclipse.kind.name) lunar eclipse at \(eclipse.peak)")
```

### Eclipse Types

- **Penumbral**: Moon passes through Earth's outer shadow
- **Partial**: Part of Moon enters Earth's umbra
- **Total**: Entire Moon enters Earth's umbra

```swift
switch eclipse.kind {
case .total:
    print("Total lunar eclipse!")
case .partial:
    print("Partial lunar eclipse")
case .penumbral:
    print("Penumbral lunar eclipse")
default:
    break
}
```

### Eclipse Timing

```swift
let eclipse = try Eclipse.searchLunar(after: .now)

print("Peak: \(eclipse.peak)")
print("Partial duration: \(eclipse.sdPartial) minutes")
print("Total duration: \(eclipse.sdTotal) minutes")  // 0 if not total
print("Penumbral duration: \(eclipse.sdPenumbra) minutes")
```

### All Eclipses in a Date Range

```swift
let eclipses = try Eclipse.lunarEclipses(
    from: AstroTime(year: 2025, month: 1, day: 1),
    to: AstroTime(year: 2026, month: 1, day: 1)
)

for eclipse in eclipses {
    print("\(eclipse.kind.name) on \(eclipse.peak)")
}
```

## Global Solar Eclipses

Global solar eclipses describe an eclipse as seen from anywhere on Earth.

### Finding the Next Solar Eclipse

```swift
let eclipse = try Eclipse.searchGlobalSolar(after: .now)
print("\(eclipse.kind.name) solar eclipse at \(eclipse.peak)")

// For total or annular eclipses, get the center line
if eclipse.kind == .total || eclipse.kind == .annular {
    if let lat = eclipse.latitude, let lon = eclipse.longitude {
        print("Path center: \(lat)°, \(lon)°")
    }
}
```

### Eclipse Types

- **Partial**: Only part of the Sun is covered
- **Annular**: Moon is too far to fully cover the Sun (ring of fire)
- **Total**: Moon completely covers the Sun

### All Solar Eclipses in a Range

```swift
let eclipses = try Eclipse.globalSolarEclipses(
    from: AstroTime(year: 2024, month: 1, day: 1),
    to: AstroTime(year: 2030, month: 1, day: 1)
)

for eclipse in eclipses {
    print("\(eclipse.kind.name): \(eclipse.peak)")
}
```

## Local Solar Eclipses

Local solar eclipses describe what an observer at a specific location will see.

### Eclipse for Your Location

```swift
let observer = Observer(latitude: 40.7128, longitude: -74.0060)
let eclipse = try Eclipse.searchLocalSolar(after: .now, from: observer)

print("Type: \(eclipse.kind.name)")
print("Obscuration: \(Int(eclipse.obscuration * 100))%")
```

### Detailed Timing

```swift
let eclipse = try Eclipse.searchLocalSolar(after: .now, from: observer)

print("Partial begins: \(eclipse.partialBegin.time)")
print("Peak: \(eclipse.peak.time)")
print("Partial ends: \(eclipse.partialEnd.time)")

// For total/annular eclipses
if let totalBegin = eclipse.totalBegin,
   let totalEnd = eclipse.totalEnd {
    print("Totality: \(totalBegin.time) to \(totalEnd.time)")
}
```

### Eclipse Visibility

Each event includes altitude information:

```swift
let event = eclipse.peak
print("Time: \(event.time)")
print("Sun altitude: \(event.altitude)°")

if event.isVisible {
    print("Sun is above the horizon")
}

if eclipse.isVisible {
    print("At least part of the eclipse is visible")
}
```

### All Local Eclipses in a Range

```swift
let observer = Observer(latitude: 35.0, longitude: -120.0)
let eclipses = try Eclipse.localSolarEclipses(
    from: .now,
    to: .now.addingDays(365 * 10),
    from: observer
)

for eclipse in eclipses {
    if eclipse.obscuration > 0.5 {
        print("Notable eclipse: \(Int(eclipse.obscuration * 100))% on \(eclipse.peak.time)")
    }
}
```

## Eclipse Search Tips

1. **Search far ahead**: Eclipses are rare—search years in advance
2. **Check visibility**: Local eclipses may occur when the Sun is below the horizon
3. **Consider obscuration**: Even partial eclipses can be interesting when obscuration is high
