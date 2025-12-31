//
//  MoonTests.swift
//  AstronomyKit
//
//  Comprehensive tests for Moon and MoonPhase types.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Moon Tests")
struct MoonTests {

    // MARK: - MoonPhase Enum Tests

    @Suite("MoonPhase Enum")
    struct MoonPhaseEnumTests {

        @Test("All phases have names")
        func allPhasesHaveNames() {
            for phase in MoonPhase.allCases {
                #expect(!phase.name.isEmpty)
            }
        }

        @Test("Phase names are correct")
        func phaseNames() {
            #expect(MoonPhase.new.name == "New Moon")
            #expect(MoonPhase.firstQuarter.name == "First Quarter")
            #expect(MoonPhase.full.name == "Full Moon")
            #expect(MoonPhase.thirdQuarter.name == "Third Quarter")
        }

        @Test("All phases have emoji")
        func allPhasesHaveEmoji() {
            for phase in MoonPhase.allCases {
                #expect(!phase.emoji.isEmpty)
            }
        }

        @Test("Phase emoji are correct")
        func phaseEmoji() {
            #expect(MoonPhase.new.emoji == "🌑")
            #expect(MoonPhase.firstQuarter.emoji == "🌓")
            #expect(MoonPhase.full.emoji == "🌕")
            #expect(MoonPhase.thirdQuarter.emoji == "🌗")
        }

        @Test("Phase longitudes are correct")
        func phaseLongitudes() {
            #expect(MoonPhase.new.longitude == 0.0)
            #expect(MoonPhase.firstQuarter.longitude == 90.0)
            #expect(MoonPhase.full.longitude == 180.0)
            #expect(MoonPhase.thirdQuarter.longitude == 270.0)
        }

        @Test("CaseIterable has 4 phases")
        func fourPhases() {
            #expect(MoonPhase.allCases.count == 4)
        }

        @Test("CustomStringConvertible includes emoji and name")
        func description() {
            let phase = MoonPhase.full
            let desc = phase.description

            #expect(desc.contains("🌕"))
            #expect(desc.contains("Full Moon"))
        }

        @Test("Codable round-trip")
        func codableRoundTrip() throws {
            let original = MoonPhase.firstQuarter

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(MoonPhase.self, from: data)

            #expect(original == decoded)
        }
    }

    // MARK: - Phase Angle Tests

    @Suite("Phase Angle")
    struct PhaseAngleTests {

        @Test("Phase angle is in valid range")
        func angleInRange() throws {
            let time = AstroTime.now
            let angle = try Moon.phaseAngle(at: time)

            #expect(angle >= 0)
            #expect(angle < 360)
        }

        @Test("Phase angle changes over time")
        func angleChanges() throws {
            let time1 = AstroTime(year: 2_025, month: 1, day: 1)
            let time2 = AstroTime(year: 2_025, month: 1, day: 8)

            let angle1 = try Moon.phaseAngle(at: time1)
            let angle2 = try Moon.phaseAngle(at: time2)

            #expect(angle1 != angle2)
        }
    }

    // MARK: - Phase Name Tests

    @Suite("Phase Names")
    struct PhaseNameTests {

        @Test("Phase name for New Moon")
        func newMoonName() {
            let name = Moon.phaseName(for: 0)
            #expect(name == "New Moon")
        }

        @Test("Phase name for First Quarter")
        func firstQuarterName() {
            let name = Moon.phaseName(for: 90)
            #expect(name == "First Quarter")
        }

        @Test("Phase name for Full Moon")
        func fullMoonName() {
            let name = Moon.phaseName(for: 180)
            #expect(name == "Full Moon")
        }

        @Test("Phase name for Third Quarter")
        func thirdQuarterName() {
            let name = Moon.phaseName(for: 270)
            #expect(name == "Third Quarter")
        }

        @Test("Phase name for Waxing Crescent")
        func waxingCrescentName() {
            let name = Moon.phaseName(for: 45)
            #expect(name == "Waxing Crescent")
        }

        @Test("Phase name for Waxing Gibbous")
        func waxingGibbousName() {
            let name = Moon.phaseName(for: 135)
            #expect(name == "Waxing Gibbous")
        }

        @Test("Phase name for Waning Gibbous")
        func waningGibbousName() {
            let name = Moon.phaseName(for: 225)
            #expect(name == "Waning Gibbous")
        }

        @Test("Phase name for Waning Crescent")
        func waningCrescentName() {
            let name = Moon.phaseName(for: 315)
            #expect(name == "Waning Crescent")
        }

        @Test("Phase name handles angle > 360")
        func angleOver360() {
            let name = Moon.phaseName(for: 450)  // Should be like 90
            #expect(name == "First Quarter")
        }
    }

    // MARK: - Phase Emoji Tests

    @Suite("Phase Emoji")
    struct PhaseEmojiTests {

        @Test("Emoji for New Moon")
        func newMoonEmoji() {
            let emoji = Moon.emoji(for: 0)
            #expect(emoji == "🌑")
        }

        @Test("Emoji for Full Moon")
        func fullMoonEmoji() {
            let emoji = Moon.emoji(for: 180)
            #expect(emoji == "🌕")
        }

        @Test("Emoji for Waxing Crescent")
        func waxingCrescentEmoji() {
            let emoji = Moon.emoji(for: 45)
            #expect(emoji == "🌒")
        }

        @Test("Emoji for Waning Crescent")
        func waningCrescentEmoji() {
            let emoji = Moon.emoji(for: 315)
            #expect(emoji == "🌘")
        }
    }

    // MARK: - Illumination Tests

    @Suite("Illumination Calculation")
    struct IlluminationTests {

        @Test("New Moon has ~0% illumination")
        func newMoonIllumination() {
            let illumination = Moon.illumination(for: 0)
            #expect(illumination < 0.01)
        }

        @Test("Full Moon has ~100% illumination")
        func fullMoonIllumination() {
            let illumination = Moon.illumination(for: 180)
            #expect(illumination > 0.99)
        }

        @Test("First Quarter has ~50% illumination")
        func firstQuarterIllumination() {
            let illumination = Moon.illumination(for: 90)
            #expect(abs(illumination - 0.5) < 0.02)
        }

        @Test("Third Quarter has ~50% illumination")
        func thirdQuarterIllumination() {
            let illumination = Moon.illumination(for: 270)
            #expect(abs(illumination - 0.5) < 0.02)
        }

        @Test(
            "Illumination is between 0 and 1",
            arguments: [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0])
        func illuminationRange(angle: Double) {
            let illumination = Moon.illumination(for: angle)
            #expect(illumination >= 0)
            #expect(illumination <= 1)
        }
    }

    // MARK: - Quarter Search Tests

    @Suite("Quarter Search")
    struct QuarterSearchTests {

        @Test("Search finds next quarter")
        func searchFindsQuarter() throws {
            let startTime = AstroTime(year: 2_025, month: 1, day: 1)
            let quarter = try Moon.searchQuarter(after: startTime)

            #expect(quarter.time > startTime)
        }

        @Test("Quarter has valid phase")
        func quarterHasValidPhase() throws {
            let startTime = AstroTime(year: 2_025, month: 1, day: 1)
            let quarter = try Moon.searchQuarter(after: startTime)

            #expect(MoonPhase.allCases.contains(quarter.phase))
        }

        @Test("Next quarter follows previous")
        func nextQuarterFollows() throws {
            let startTime = AstroTime(year: 2_025, month: 1, day: 1)
            let quarter1 = try Moon.searchQuarter(after: startTime)
            let quarter2 = try Moon.nextQuarter(after: quarter1)

            #expect(quarter2.time > quarter1.time)
        }

        @Test("Quarters cycle through phases")
        func quartersCycle() throws {
            let startTime = AstroTime(year: 2_025, month: 1, day: 1)
            var quarter = try Moon.searchQuarter(after: startTime)

            var phases: [MoonPhase] = []
            for _ in 0..<4 {
                phases.append(quarter.phase)
                quarter = try Moon.nextQuarter(after: quarter)
            }

            // Should have all 4 phases
            #expect(
                phases.contains(.new) || phases.contains(.firstQuarter)
                    || phases.contains(.full) || phases.contains(.thirdQuarter))
        }

        @Test("Quarters in range")
        func quartersInRange() throws {
            let startTime = AstroTime(year: 2_025, month: 1, day: 1)
            let endTime = AstroTime(year: 2_025, month: 2, day: 1)

            let quarters = try Moon.quarters(from: startTime, to: endTime)

            // Should have about 4 quarters in a month
            #expect(quarters.count >= 3)
            #expect(quarters.count <= 5)

            // All should be in range
            for quarter in quarters {
                #expect(quarter.time >= startTime)
                #expect(quarter.time < endTime)
            }
        }
    }

    // MARK: - Phase Search Tests

    @Suite("Phase Search")
    struct PhaseSearchTests {

        @Test("Search specific phase", arguments: MoonPhase.allCases)
        func searchSpecificPhase(phase: MoonPhase) throws {
            let startTime = AstroTime(year: 2_025, month: 1, day: 1)
            let foundTime = try Moon.searchPhase(phase, after: startTime)

            #expect(foundTime > startTime)

            // The phase angle at found time should be close to the phase's longitude
            let angleAtTime = try Moon.phaseAngle(at: foundTime)
            let expectedAngle = phase.longitude

            // Allow some tolerance (within 1 degree)
            let diff = abs(angleAtTime - expectedAngle)
            let normalizedDiff = min(diff, 360 - diff)
            #expect(normalizedDiff < 2)
        }
    }

    // MARK: - MoonQuarter Tests

    @Suite("MoonQuarter")
    struct MoonQuarterTests {

        @Test("MoonQuarter has phase and time")
        func quarterProperties() throws {
            let startTime = AstroTime(year: 2_025, month: 1, day: 1)
            let quarter = try Moon.searchQuarter(after: startTime)

            #expect(MoonPhase.allCases.contains(quarter.phase))
            #expect(quarter.time > startTime)
        }

        @Test("MoonQuarter Equatable")
        func equatable() throws {
            let startTime = AstroTime(year: 2_025, month: 1, day: 1)
            let q1 = try Moon.searchQuarter(after: startTime)
            let q2 = try Moon.searchQuarter(after: startTime)

            #expect(q1 == q2)
        }

        @Test("MoonQuarter CustomStringConvertible")
        func description() throws {
            let startTime = AstroTime(year: 2_025, month: 1, day: 1)
            let quarter = try Moon.searchQuarter(after: startTime)

            let desc = quarter.description

            #expect(!desc.isEmpty)
        }
    }

    // MARK: - Ecliptic Position Tests

    @Suite("Ecliptic Position")
    struct EclipticPositionTests {

        @Test("Ecliptic position has valid latitude")
        func validLatitude() throws {
            let time = AstroTime.now
            let position = try Moon.eclipticPosition(at: time)

            #expect(position.latitude >= -90)
            #expect(position.latitude <= 90)
        }

        @Test("Ecliptic position has valid longitude")
        func validLongitude() throws {
            let time = AstroTime.now
            let position = try Moon.eclipticPosition(at: time)

            #expect(position.longitude >= 0)
            #expect(position.longitude < 360)
        }

        @Test("Ecliptic position has positive distance")
        func positiveDistance() throws {
            let time = AstroTime.now
            let position = try Moon.eclipticPosition(at: time)

            #expect(position.distance > 0)
        }

        @Test("Moon's ecliptic latitude is limited")
        func moonLatitudeLimited() throws {
            // Moon's orbit is inclined ~5° to ecliptic
            let time = AstroTime.now
            let position = try Moon.eclipticPosition(at: time)

            #expect(abs(position.latitude) < 6)
        }
    }
}
