import AstronomyKit
import Foundation
import Testing

/// Test to verify that Pluto calculations are thread-safe after mutex fix.
/// This test runs multiple Pluto calculations in parallel to detect race conditions.
@Suite("Pluto Thread Safety")
struct PlutoThreadSafetyTests {

    /// Helper to convert equatorial coordinates to ecliptic longitude
    private func equatorialToEclipticLongitude(ra: Double, dec: Double) -> Double {
        let obliquity = 23.4393 * .pi / 180.0
        let raRad = ra * 15.0 * .pi / 180.0
        let decRad = dec * .pi / 180.0
        let sinLon = sin(raRad) * cos(obliquity) + tan(decRad) * sin(obliquity)
        let cosLon = cos(raRad)
        var lon = atan2(sinLon, cosLon) * 180.0 / .pi
        if lon < 0 { lon += 360.0 }
        return lon
    }

    /// ±1 arcminute tolerance (1/60° ≈ 0.0167°)
    static let arcminuteTolerance: Double = 1.0 / 60.0

    // Reference values for Pluto at different dates (from Swiss Ephemeris)
    // These are absolute ecliptic longitudes in degrees
    struct PlutoReference {
        let dateISO: String
        let expectedLongitude: Double  // degrees
    }

    // 2027-01-02: Pluto at 04°23'29" Aquarius = 300 + 4 + 23/60 + 29/3600 = 304.391°
    // 2028-01-02: Pluto at 06°00'40" Aquarius = 300 + 6 + 0/60 + 40/3600 = 306.011°
    // 2031-01-02: Pluto at 10°46'34" Aquarius = 300 + 10 + 46/60 + 34/3600 = 310.776°
    // 2036-01-02: Pluto at 18°18'58" Aquarius = 300 + 18 + 18/60 + 58/3600 = 318.316°
    // 2051-01-02: Pluto at 08°49'41" Pisces = 330 + 8 + 49/60 + 41/3600 = 338.828°
    // 2076-01-02: Pluto at 07°54'54" Aries = 0 + 7 + 54/60 + 54/3600 = 7.915°
    // 2126-01-02: Pluto at 27°19'00" Taurus = 30 + 27 + 19/60 + 0/3600 = 57.317°

    static let plutoReferences: [PlutoReference] = [
        PlutoReference(dateISO: "2027-01-02T08:30:00Z", expectedLongitude: 304.391),
        PlutoReference(dateISO: "2028-01-02T14:15:00Z", expectedLongitude: 306.011),
        PlutoReference(dateISO: "2031-01-02T21:45:00Z", expectedLongitude: 310.776),
        PlutoReference(dateISO: "2036-01-02T03:00:00Z", expectedLongitude: 318.316),
        PlutoReference(dateISO: "2051-01-02T12:00:00Z", expectedLongitude: 338.828),
        PlutoReference(dateISO: "2076-01-02T18:30:00Z", expectedLongitude: 7.915),
        PlutoReference(dateISO: "2126-01-02T00:00:00Z", expectedLongitude: 57.317),
    ]

    @Test("Pluto 2027 position is accurate")
    func pluto2027() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: "2027-01-02T08:30:00Z")!
        let time = AstroTime(date)

        let plutoEq = try CelestialBody.pluto.equatorial(at: time, equatorDate: .ofDate)
        let plutoLon = equatorialToEclipticLongitude(
            ra: plutoEq.rightAscension, dec: plutoEq.declination)

        #expect(
            abs(plutoLon - 304.391) < Self.arcminuteTolerance,
            "Pluto 2027: \(plutoLon)° vs ref 304.391°"
        )
    }

    @Test("Pluto 2028 position is accurate")
    func pluto2028() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: "2028-01-02T14:15:00Z")!
        let time = AstroTime(date)

        let plutoEq = try CelestialBody.pluto.equatorial(at: time, equatorDate: .ofDate)
        let plutoLon = equatorialToEclipticLongitude(
            ra: plutoEq.rightAscension, dec: plutoEq.declination)

        #expect(
            abs(plutoLon - 306.011) < Self.arcminuteTolerance,
            "Pluto 2028: \(plutoLon)° vs ref 306.011°"
        )
    }

    @Test("Pluto 2031 position is accurate")
    func pluto2031() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: "2031-01-02T21:45:00Z")!
        let time = AstroTime(date)

        let plutoEq = try CelestialBody.pluto.equatorial(at: time, equatorDate: .ofDate)
        let plutoLon = equatorialToEclipticLongitude(
            ra: plutoEq.rightAscension, dec: plutoEq.declination)

        #expect(
            abs(plutoLon - 310.776) < Self.arcminuteTolerance,
            "Pluto 2031: \(plutoLon)° vs ref 310.776°"
        )
    }

    @Test("Pluto 2036 position is accurate")
    func pluto2036() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: "2036-01-02T03:00:00Z")!
        let time = AstroTime(date)

        let plutoEq = try CelestialBody.pluto.equatorial(at: time, equatorDate: .ofDate)
        let plutoLon = equatorialToEclipticLongitude(
            ra: plutoEq.rightAscension, dec: plutoEq.declination)

        #expect(
            abs(plutoLon - 318.316) < Self.arcminuteTolerance,
            "Pluto 2036: \(plutoLon)° vs ref 318.316°"
        )
    }

    @Test("Pluto 2051 position is accurate")
    func pluto2051() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: "2051-01-02T12:00:00Z")!
        let time = AstroTime(date)

        let plutoEq = try CelestialBody.pluto.equatorial(at: time, equatorDate: .ofDate)
        let plutoLon = equatorialToEclipticLongitude(
            ra: plutoEq.rightAscension, dec: plutoEq.declination)

        #expect(
            abs(plutoLon - 338.828) < Self.arcminuteTolerance,
            "Pluto 2051: \(plutoLon)° vs ref 338.828°"
        )
    }

    @Test("Pluto 2076 position is accurate")
    func pluto2076() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: "2076-01-02T18:30:00Z")!
        let time = AstroTime(date)

        let plutoEq = try CelestialBody.pluto.equatorial(at: time, equatorDate: .ofDate)
        let plutoLon = equatorialToEclipticLongitude(
            ra: plutoEq.rightAscension, dec: plutoEq.declination)

        #expect(
            abs(plutoLon - 7.915) < Self.arcminuteTolerance,
            "Pluto 2076: \(plutoLon)° vs ref 7.915°"
        )
    }

    @Test("Pluto 2126 position is accurate")
    func pluto2126() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: "2126-01-02T00:00:00Z")!
        let time = AstroTime(date)

        let plutoEq = try CelestialBody.pluto.equatorial(at: time, equatorDate: .ofDate)
        let plutoLon = equatorialToEclipticLongitude(
            ra: plutoEq.rightAscension, dec: plutoEq.declination)

        #expect(
            abs(plutoLon - 57.317) < Self.arcminuteTolerance,
            "Pluto 2126: \(plutoLon)° vs ref 57.317°"
        )
    }
}
