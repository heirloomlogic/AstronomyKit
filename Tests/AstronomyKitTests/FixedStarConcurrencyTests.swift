import AstronomyKit
import Foundation
import Testing

/// Verifies that the per-slot fixed-star pool is thread-safe: many distinct stars
/// mapped across the eight C star slots must produce the same results concurrently
/// as they do serially, and repeated calls for a single star (which hit the
/// definition-cache skip path) must stay consistent.
@Suite("Fixed Star Concurrency")
struct FixedStarConcurrencyTests {
    /// A distinct star with a precomputed serial reference position.
    struct Reference {
        let star: FixedStar
        let longitude: Double
        let latitude: Double
        let distance: Double
    }

    static let time = AstroTime(year: 2_025, month: 6, day: 21)

    /// Sixteen distinct stars spread across right ascension, declination, and distance
    /// so that they hash into a mix of the eight available slots.
    static let stars: [FixedStar] = (0..<16).map { i in
        FixedStar(
            name: "Star\(i)",
            rightAscension: Double(i) * 1.5,
            declination: -80.0 + Double(i) * 10.0,
            distance: 10.0 + Double(i) * 7.5
        )
    }

    /// Serial reference positions computed one star at a time.
    private func serialReferences() throws -> [Reference] {
        try Self.stars.map { star in
            let ecliptic = try star.ecliptic(at: Self.time)
            return Reference(
                star: star,
                longitude: ecliptic.longitude,
                latitude: ecliptic.latitude,
                distance: ecliptic.distance
            )
        }
    }

    @Test("Concurrent distinct-star lookups match serial references")
    func concurrentDistinctStarsAreConsistent() async throws {
        let references = try serialReferences()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    for reference in references {
                        let ecliptic = try reference.star.ecliptic(at: Self.time)
                        #expect(ecliptic.longitude == reference.longitude)
                        #expect(ecliptic.latitude == reference.latitude)
                        #expect(ecliptic.distance == reference.distance)
                    }
                }
            }

            try await group.waitForAll()
        }
    }

    @Test("Repeated same-star lookups stay consistent (definition-cache skip path)")
    func repeatedSameStarIsConsistent() async throws {
        let star = FixedStar(
            name: "Algol",
            rightAscension: 3.136148,
            declination: 40.9556,
            distance: 92.95
        )

        // Serial reference for a single star, exercising the cached-definition path.
        let reference = try star.ecliptic(at: Self.time)
        for _ in 0..<50 {
            let ecliptic = try star.ecliptic(at: Self.time)
            #expect(ecliptic.longitude == reference.longitude)
            #expect(ecliptic.latitude == reference.latitude)
            #expect(ecliptic.distance == reference.distance)
        }

        // Hammer the same star from many tasks; all share one slot and skip redefinition.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    for _ in 0..<50 {
                        let ecliptic = try star.ecliptic(at: Self.time)
                        #expect(ecliptic.longitude == reference.longitude)
                        #expect(ecliptic.latitude == reference.latitude)
                        #expect(ecliptic.distance == reference.distance)
                    }
                }
            }

            try await group.waitForAll()
        }
    }
}
