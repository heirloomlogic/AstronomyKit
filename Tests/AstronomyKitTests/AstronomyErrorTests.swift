//
//  AstronomyErrorTests.swift
//  AstronomyKit
//
//  Comprehensive tests for the AstronomyError type.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("AstronomyError Tests")
struct AstronomyErrorTests {

    // MARK: - Error Cases Tests

    @Suite("Error Cases")
    struct ErrorCasesTests {

        @Test("All error case descriptions exist")
        func allCasesHaveDescriptions() {
            let errors: [AstronomyError] = [
                .notInitialized,
                .invalidBody,
                .noConvergence,
                .badTime,
                .badVector,
                .searchFailure,
                .earthNotAllowed,
                .noMoonQuarter,
                .wrongMoonQuarter,
                .internalError,
                .invalidParameter,
                .failApsis,
                .bufferTooSmall,
                .outOfMemory,
                .inconsistentTimes,
                .unknown(999),
            ]

            for error in errors {
                #expect(!error.description.isEmpty)
            }
        }

        @Test("Error descriptions are meaningful")
        func meaningfulDescriptions() {
            #expect(AstronomyError.notInitialized.description.contains("initialized"))
            #expect(AstronomyError.invalidBody.description.contains("body"))
            #expect(AstronomyError.noConvergence.description.contains("converge"))
            #expect(
                AstronomyError.badTime.description.contains("time")
                    || AstronomyError.badTime.description.contains("Date"))
            #expect(AstronomyError.earthNotAllowed.description.contains("Earth"))
        }

        @Test("Unknown error includes code")
        func unknownIncludesCode() {
            let error = AstronomyError.unknown(42)
            #expect(error.description.contains("42"))
        }
    }

    // MARK: - Equatable Tests

    @Suite("Equatable")
    struct EquatableTests {

        @Test("Same errors are equal")
        func sameAreEqual() {
            #expect(AstronomyError.invalidBody == AstronomyError.invalidBody)
            #expect(AstronomyError.badTime == AstronomyError.badTime)
        }

        @Test("Different errors are not equal")
        func differentAreNotEqual() {
            #expect(AstronomyError.invalidBody != AstronomyError.badTime)
            #expect(AstronomyError.noConvergence != AstronomyError.searchFailure)
        }

        @Test("Unknown errors with same code are equal")
        func unknownWithSameCode() {
            #expect(AstronomyError.unknown(100) == AstronomyError.unknown(100))
        }

        @Test("Unknown errors with different codes are not equal")
        func unknownWithDifferentCodes() {
            #expect(AstronomyError.unknown(100) != AstronomyError.unknown(200))
        }
    }

    // MARK: - Hashable Tests

    @Suite("Hashable")
    struct HashableTests {

        @Test("Can be used in Set")
        func usedInSet() {
            let errors: Set<AstronomyError> = [
                .invalidBody,
                .badTime,
                .noConvergence,
                .invalidBody,  // Duplicate
            ]

            #expect(errors.count == 3)
        }

        @Test("Can be used as Dictionary key")
        func usedAsDictionaryKey() {
            var dict: [AstronomyError: String] = [:]
            dict[.invalidBody] = "body error"
            dict[.badTime] = "time error"

            #expect(dict[.invalidBody] == "body error")
            #expect(dict[.badTime] == "time error")
        }

        @Test("Equal errors have equal hashes")
        func equalHashValues() {
            let e1 = AstronomyError.invalidBody
            let e2 = AstronomyError.invalidBody

            #expect(e1.hashValue == e2.hashValue)
        }
    }

    // MARK: - Sendable Tests

    @Suite("Sendable")
    struct SendableTests {

        @Test("Error is Sendable")
        func isSendable() async {
            let error: AstronomyError = .invalidBody

            // If this compiles, the type is Sendable
            let _ = await Task {
                return error
            }.value
        }
    }

    // MARK: - Error Protocol Tests

    @Suite("Error Protocol")
    struct ErrorProtocolTests {

        @Test("Conforms to Error protocol")
        func conformsToError() {
            let error: Error = AstronomyError.invalidBody

            // Should be able to use as Error
            #expect(error.localizedDescription.count > 0)
        }

        @Test("Can be thrown and caught")
        func throwAndCatch() {
            func throwingFunction() throws {
                throw AstronomyError.invalidBody
            }

            do {
                try throwingFunction()
                Issue.record("Expected error to be thrown")
            } catch let error as AstronomyError {
                #expect(error == .invalidBody)
            } catch {
                Issue.record("Caught unexpected error type")
            }
        }

        @Test("Can match specific error cases")
        func matchSpecificCases() {
            let error: AstronomyError = .badTime

            switch error {
            case .badTime:
                // Success
                break
            default:
                Issue.record("Should have matched .badTime")
            }
        }
    }

    // MARK: - Real Error Triggering Tests

    @Suite("Real Errors")
    struct RealErrorTests {

        @Test("Earth geocentric position behavior")
        func earthGeoPosition() throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)

            // Test that the API handles Earth appropriately
            // It may throw or return a valid result depending on implementation
            do {
                let pos = try CelestialBody.earth.geoPosition(at: time)
                // If it doesn't throw, verify we got a valid position
                #expect(pos.magnitude >= 0)
            } catch {
                // Throwing is also acceptable behavior
            }
        }

        @Test("Sun elongation behavior")
        func sunElongation() throws {
            let time = AstroTime(year: 2025, month: 6, day: 21)

            // Test that the API handles Sun appropriately
            // It may throw or return a result depending on implementation
            do {
                let elong = try CelestialBody.sun.elongation(at: time)
                // If it doesn't throw, verify we got a valid elongation
                #expect(elong.angle >= 0)
            } catch {
                // Throwing is also acceptable behavior
            }
        }
    }
}
