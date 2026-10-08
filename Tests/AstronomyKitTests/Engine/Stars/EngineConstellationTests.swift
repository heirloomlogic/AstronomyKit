import Testing

@testable import AstronomyKit

@Suite("Native constellation lookup")
struct EngineConstellationTests {
    private let archive = IndependentReferenceArchive.shared

    @Test("All 88 published symbols map to their published names")
    func allPublishedNames() throws {
        #expect(archive.constellations.count == 88)
        let names = Dictionary(uniqueKeysWithValues: archive.constellations.map { ($0.symbol, $0.name) })
        #expect(names.count == 88)
        #expect(names["Ant"] == "Antlia")
        for reference in archive.constellationNearBoundaryStars {
            let result = try Engine.Constellations.find(
                rightAscension: reference.rightAscensionHoursJ2000,
                declination: reference.declinationDegreesJ2000
            )
            #expect(result.name == names[result.symbol])
        }
        #expect(Set(archive.constellationNearBoundaryStars.map(\.symbol)) == Set(names.keys))
    }

    @Test("Every published segment and exact boundary tie follows VI/42")
    func everyBoundaryTie() throws {
        #expect(archive.constellationBoundaries.count == 357)
        #expect(archive.constellationBoundaryTies.count == 1_071)
        for tie in archive.constellationBoundaryTies {
            let result = try Engine.Constellations.findB1875(
                rightAscension: tie.rightAscensionHours,
                declination: tie.declinationDegrees
            )
            #expect(result.symbol == tie.symbol, "VI/42 boundary \(tie.boundaryIndex) \(tie.kind)")
        }
    }

    @Test("A J2000 point near every published boundary returns the published constellation")
    func everyNearBoundaryPoint() throws {
        #expect(archive.constellationNearBoundaryStars.count == 357)
        for reference in archive.constellationNearBoundaryStars {
            let result = try Engine.Constellations.find(
                rightAscension: reference.rightAscensionHoursJ2000,
                declination: reference.declinationDegreesJ2000
            )
            #expect(result.symbol == reference.symbol, "VI/42 boundary \(reference.boundaryIndex ?? -1)")
            #expect(abs(result.rightAscension1875 - reference.rightAscensionHoursB1875) < 1e-9)
            #expect(abs(result.declination1875 - reference.declinationDegreesB1875) < 1e-9)
        }
    }

    @Test("The eight VI/42 examples retain their published classifications")
    func publishedExamples() throws {
        #expect(archive.constellationPublishedExamples.count == 8)
        for reference in archive.constellationPublishedExamples {
            let result = try Engine.Constellations.find(
                rightAscension: reference.rightAscensionHoursJ2000,
                declination: reference.declinationDegreesJ2000
            )
            #expect(result.symbol == reference.symbol)
            #expect(abs(result.rightAscension1875 - reference.rightAscensionHoursB1875) < 1e-9)
            #expect(abs(result.declination1875 - reference.declinationDegreesB1875) < 1e-9)
        }
    }

    @Test("Right ascension wraps and non-finite or out-of-range coordinates fail")
    func coordinateValidation() throws {
        let reference = try Engine.Constellations.find(rightAscension: 5.9195, declination: 7.4071)
        for rightAscension in [5.9195 - 48, 5.9195 - 24, 5.9195 + 24, 5.9195 + 48] {
            let wrapped = try Engine.Constellations.find(rightAscension: rightAscension, declination: 7.4071)
            #expect(wrapped.symbol == reference.symbol)
            #expect(wrapped.name == reference.name)
            #expect(abs(wrapped.rightAscension1875 - reference.rightAscension1875) < 1e-12)
            #expect(abs(wrapped.declination1875 - reference.declination1875) < 1e-12)
        }
        for rightAscension in [Double.nan, .infinity, -.infinity] {
            #expect(throws: AstronomyError.invalidParameter) {
                try Engine.Constellations.find(rightAscension: rightAscension, declination: 0)
            }
        }
        for declination in [Double.nan, .infinity, -.infinity, -90.000_001, 90.000_001] {
            #expect(throws: AstronomyError.invalidParameter) {
                try Engine.Constellations.find(rightAscension: 0, declination: declination)
            }
        }
    }

    @Test("Valid directions that rotate onto either B1875 pole remain valid")
    func polarRounding() throws {
        let directions = [
            (rightAscension: 12.053_363_452_449_263, declination: 89.304_062_550_348_75, symbol: "UMi"),
            (rightAscension: 0.053_363_452_449_263, declination: -89.304_062_550_348_75, symbol: "Oct"),
        ]
        for direction in directions {
            for offset in [-1e-7, 0, 1e-7] {
                let result = try Engine.Constellations.find(
                    rightAscension: direction.rightAscension,
                    declination: direction.declination + offset
                )
                #expect(result.symbol == direction.symbol)
                #expect((-90...90).contains(result.declination1875))
            }
        }
    }

    @Test("Tiny negative right ascensions round through zero instead of 24 hours")
    func negativeRightAscensionRounding() throws {
        let zero = try Engine.Constellations.findB1875(rightAscension: 0, declination: 0)
        for rightAscension in [-Double.leastNonzeroMagnitude, -1e-16, -24, 24, 48] {
            let result = try Engine.Constellations.findB1875(
                rightAscension: rightAscension,
                declination: 0
            )
            #expect(result.symbol == zero.symbol)
            #expect(result.rightAscension1875 == 0)
        }
    }

    @Test("Published B1875 rotation is independent of the old first-call Delta T and nutation path")
    func fixedPublishedRotation() {
        let universalTime = -45_655.741_412_610_17
        let historicalOutput = Engine.Time.fromPair(
            ut: universalTime,
            tt: universalTime + 3.2 / Engine.secondsPerDay,
            deltaTModel: .espenakMeeus
        )
        let distinctModelOutput = Engine.Time.fromPair(
            ut: universalTime,
            tt: universalTime + 3_600 / Engine.secondsPerDay,
            deltaTModel: .espenakMeeus
        )

        let oldHistoricalOutput = Engine.FrameRotation.eqjToEqd(historicalOutput)
        let oldDistinctModelOutput = Engine.FrameRotation.eqjToEqd(distinctModelOutput)
        var oldModelsDiffer = false
        var publishedDiffersFromOld = false
        for row in 0..<3 {
            for column in 0..<3 {
                oldModelsDiffer =
                    oldModelsDiffer || oldHistoricalOutput[row, column] != oldDistinctModelOutput[row, column]
                publishedDiffersFromOld =
                    publishedDiffersFromOld
                    || Engine.Constellations.b1875Rotation[row, column] != oldHistoricalOutput[row, column]
            }
        }
        #expect(oldModelsDiffer)
        #expect(publishedDiffersFromOld)
    }
}
