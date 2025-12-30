//
//  UserStarTests.swift
//  AstronomyKit
//
//  Tests for user-defined star functionality.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("User Star Tests")
struct UserStarTests {

    @Test("User star slots exist")
    func userStarSlots() {
        #expect(CelestialBody.userStars.count == 8)
        #expect(CelestialBody.userStars.contains(.star1))
        #expect(CelestialBody.userStars.contains(.star8))
    }

    @Test("isUserStar property")
    func isUserStarProperty() {
        #expect(CelestialBody.star1.isUserStar)
        #expect(CelestialBody.star8.isUserStar)
        #expect(!CelestialBody.mars.isUserStar)
        #expect(!CelestialBody.sun.isUserStar)
    }

    @Test("Define star requires user star slot")
    func defineStarRequiresUserSlot() throws {
        // Should fail for non-user star
        do {
            try CelestialBody.mars.define(ra: 6.75, dec: -16.72, distanceLightYears: 8.6)
            #expect(Bool(false), "Should have thrown")
        } catch is AstronomyError {
            // Expected - mars is not a user star slot
        }
    }

    @Test("Define and use star")
    func defineAndUseStar() throws {
        // Define Sirius at star1
        try CelestialBody.star1.define(
            ra: 6.7525,
            dec: -16.7161,
            distanceLightYears: 8.6
        )

        // Should now be able to get position
        let eq = try CelestialBody.star1.equatorial(at: .now)

        // RA should be close to where we defined it
        #expect(eq.rightAscension > 6 && eq.rightAscension < 7.5)
    }

    @Test("User stars are in allCases")
    func userStarsInAllCases() {
        #expect(CelestialBody.allCases.contains(.star1))
        #expect(CelestialBody.allCases.contains(.star8))
    }

    @Test("User stars are Codable")
    func userStarsCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(CelestialBody.star1)
        let decoded = try decoder.decode(CelestialBody.self, from: data)

        #expect(decoded == .star1)
    }

    @Test("Star names from C library")
    func starNames() {
        // The C library returns empty strings for user stars until defined
        // Just verify name property is accessible
        let name = CelestialBody.star1.name
        #expect(name != nil)  // Just check it doesn't crash
    }
}
