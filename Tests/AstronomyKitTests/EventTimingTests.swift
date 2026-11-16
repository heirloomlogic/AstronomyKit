import AstronomyKit
import Testing

/// Times of stations, solar band crossings, and an equinox against JPL Horizons.
///
/// Each reference is a zero of the apparent geocentric ecliptic-of-date longitude that
/// Horizons tabulates (DE441, observer table quantity 31, geocentric, Terrestrial Time,
/// every ten minutes for a day around the event, retrieved 2026-11-15): of its rate for
/// a station, of the planet's longitude less the Sun's less the offset for a band
/// crossing, and of the longitude less the target for a longitude crossing. A
/// sixth-degree fit to the table locates the zero.
///
/// Before the planet series were lengthened, these events were 19 to 393 seconds from
/// the references. They are now within 29: the Mars and Venus stations are the furthest,
/// held there by the five-term nutation series.
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

    @Test("Events fall within 40 seconds of JPL Horizons", arguments: references)
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
        #expect(abs(seconds) < 40, "\(seconds) seconds from Horizons")
    }
}
