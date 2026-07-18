import AstronomyKit
import Testing

/// Verifies that the constellation rotation matrix's lazy initialization is
/// thread-safe: concurrent first calls must not race on the shared state that
/// `Astronomy_Constellation` initializes once.
@Suite("Constellation Thread Safety")
struct ConstellationThreadSafetyTests {
    /// Known coordinates and the constellation that contains them.
    struct Reference {
        let rightAscension: Double
        let declination: Double
        let symbol: String
    }

    static let references: [Reference] = [
        // Polaris (the North Star) is in Ursa Minor.
        Reference(rightAscension: 2.53, declination: 89.26, symbol: "UMi"),
        // Betelgeuse is in Orion.
        Reference(rightAscension: 5.92, declination: 7.41, symbol: "Ori"),
        // Sirius is in Canis Major.
        Reference(rightAscension: 6.752, declination: -16.716, symbol: "CMa"),
        // Vega is in Lyra.
        Reference(rightAscension: 18.615, declination: 38.784, symbol: "Lyr"),
    ]

    @Test("Concurrent constellation lookups agree on the expected constellation")
    func concurrentLookupsAreConsistent() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    for reference in Self.references {
                        let constellation = try Constellation.find(
                            rightAscension: reference.rightAscension,
                            declination: reference.declination
                        )
                        #expect(constellation.symbol == reference.symbol)
                    }
                }
            }

            try await group.waitForAll()
        }
    }
}
