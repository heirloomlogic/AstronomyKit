import AstronomyKit
import Testing

/// Times of stations, solar band crossings, and an equinox against JPL Horizons.
///
/// Each reference is a zero of the apparent geocentric ecliptic-of-date longitude that
/// Horizons tabulates (DE441, observer table quantity 31, geocentric, Terrestrial Time,
/// every ten minutes for a day around the event, retrieved 2026-11-15): of its rate for
/// a station, of the planet's longitude less the Sun's less the offset for a band
/// crossing, and of the longitude less the target for a longitude crossing. A
/// sixth-degree fit to the table locates the zero. The Jupiter and Saturn stations are
/// of the system barycentres, from three days of the table, retrieved 2026-11-17.
///
/// Before the planet series were lengthened, the first nine events were 19 to 393
/// seconds from the references. With the longer series and upstream's five nutation
/// terms they were within 29, and the Jupiter and Saturn stations were 101 to 315
/// seconds out: the slower a planet, the further the missing nutation terms move its
/// station. With all 77 terms of the nutation series the first nine are within 7
/// seconds and the Jupiter and Saturn stations within 15.
@Suite("Event timing")
struct EventTimingTests {
    enum Event: Sendable {
        /// The longitude rate is zero.
        case station
        /// The body is this many degrees of longitude ahead of the Sun.
        case aheadOfSun(Double)
        /// The body is at this longitude in degrees.
        case longitude(Double)
    }

    struct Reference: Sendable, CustomTestStringConvertible {
        let name: String
        let body: CelestialBody
        let event: Event
        /// Terrestrial Time of the event in days since J2000.
        let terrestrialTime: Double
        /// The furthest the event may fall from the reference, in seconds.
        var tolerance = 10.0

        var testDescription: String { name }
    }

    static let references = [
        Reference(
            name: "Mercury retrograde station, 2026-02-26",
            body: .mercury, event: .station, terrestrialTime: 9_552.784248905),
        Reference(
            name: "Mercury direct station, 2026-03-20",
            body: .mercury, event: .station, terrestrialTime: 9_575.315270066),
        Reference(
            name: "Venus 8.5° ahead of the Sun, 2026-10-18",
            body: .venus, event: .aheadOfSun(8.5), terrestrialTime: 9_787.292381703),
        Reference(
            name: "Venus 8.5° behind the Sun, 2026-10-29",
            body: .venus, event: .aheadOfSun(-8.5), terrestrialTime: 9_797.994866813),
        Reference(
            name: "Venus retrograde station, 2026-10-03",
            body: .venus, event: .station, terrestrialTime: 9_771.803517224),
        Reference(
            name: "Venus direct station, 2026-11-14",
            body: .venus, event: .station, terrestrialTime: 9_813.519869807),
        Reference(
            name: "Mars retrograde station, 2027-01-10",
            body: .mars, event: .station, terrestrialTime: 9_871.041899332),
        Reference(
            name: "Mars direct station, 2027-04-01",
            body: .mars, event: .station, terrestrialTime: 9_952.089881688),
        Reference(
            name: "March equinox, 2026-03-20",
            body: .sun, event: .longitude(0), terrestrialTime: 9_575.116062065),
        Reference(
            name: "Jupiter direct station, 2026-03-11",
            body: .jupiter, event: .station, terrestrialTime: 9_565.646552899, tolerance: 20),
        Reference(
            name: "Jupiter retrograde station, 2026-12-13",
            body: .jupiter, event: .station, terrestrialTime: 9_842.540104577, tolerance: 20),
        Reference(
            name: "Saturn retrograde station, 2026-07-26",
            body: .saturn, event: .station, terrestrialTime: 9_703.331519488, tolerance: 20),
        Reference(
            name: "Saturn direct station, 2026-12-10",
            body: .saturn, event: .station, terrestrialTime: 9_840.480787235, tolerance: 20),
    ]

    /// The quantity whose zero is the event.
    static func residual(_ reference: Reference, at time: AstroTime) throws -> Double {
        switch reference.event {
        case .station:
            return try reference.body.geocentricEclipticState(at: time).longitudeRate
        case .aheadOfSun(let offset):
            let body = try reference.body.geocentricPosition(at: time).toEcliptic().longitude
            let sun = try CelestialBody.sun.geocentricPosition(at: time).toEcliptic().longitude
            return EclipticStateTests.longitudeChange(sun, body) - offset
        case .longitude(let target):
            let body = try reference.body.geocentricPosition(at: time).toEcliptic().longitude
            return EclipticStateTests.longitudeChange(target, body)
        }
    }

    @Test("Events fall within seconds of JPL Horizons", arguments: references)
    func eventTime(reference: Reference) throws {
        var low = reference.terrestrialTime - 0.25
        var high = reference.terrestrialTime + 0.25
        let lowIsNegative = try Self.residual(reference, at: AstroTime(tt: low)) < 0
        let highIsNegative = try Self.residual(reference, at: AstroTime(tt: high)) < 0
        try #require(lowIsNegative != highIsNegative, "no event within six hours of the reference")

        // Bisect to a second.
        while high - low > 1e-5 {
            let middle = (low + high) / 2
            if try (Self.residual(reference, at: AstroTime(tt: middle)) < 0) == lowIsNegative {
                low = middle
            } else {
                high = middle
            }
        }
        let seconds = ((low + high) / 2 - reference.terrestrialTime) * 86_400
        #expect(abs(seconds) < reference.tolerance, "\(seconds) seconds from Horizons")
    }
}
