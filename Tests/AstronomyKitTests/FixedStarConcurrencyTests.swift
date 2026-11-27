import AstronomyKit
import Foundation
import Testing

/// Verifies that stateless fixed-star calculations are thread-safe: many
/// distinct stars evaluated concurrently must produce the same results as they
/// do serially, and repeated concurrent calls for a single star must stay
/// consistent.
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

    /// Sixteen distinct stars spread across right ascension, declination, and distance.
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

    @Test("Repeated same-star lookups stay consistent")
    func repeatedSameStarIsConsistent() async throws {
        let star = FixedStar(
            name: "Algol",
            rightAscension: 3.136148,
            declination: 40.9556,
            distance: 92.95
        )

        // Serial reference for a single star across repeated lookups.
        let reference = try star.ecliptic(at: Self.time)
        for _ in 0..<50 {
            let ecliptic = try star.ecliptic(at: Self.time)
            #expect(ecliptic.longitude == reference.longitude)
            #expect(ecliptic.latitude == reference.latitude)
            #expect(ecliptic.distance == reference.distance)
        }

        // Evaluate the same star concurrently from many tasks.
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
