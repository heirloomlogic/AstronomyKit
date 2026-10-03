import Foundation
import Testing

@testable import AstronomyKit

@Suite("Independent astronomical references")
struct AuditValidationTests {
    private enum FixtureLabelError: Error {
        case unknownApsisKind(String)
        case unknownRiseSetDirection(String)
    }

    let archive = IndependentReferenceArchive.shared

    @Test("Archived references declare reproducible provenance")
    func provenanceIsComplete() {
        #expect(archive.schemaVersion == 2)
        #expect(
            Set(archive.provenance.keys) == [
                "astronomyEngineApsides", "eclipseWiseLocalSolar", "espenakMoonNodes",
                "jplObserver", "jplVectors", "nasaGlobalSolarEclipses", "nasaLunarEclipses",
                "nasaPlanetaryTransits", "usnoRiseSet", "usnoSeasonsAndPhases",
            ])
        for source in archive.provenance.values {
            let fields = [
                source.version ?? source.serviceVersion ?? "", source.frame, source.origin, source.units,
                source.timeScale, source.aberration, source.refraction, source.domain, source.license,
                source.url, source.recipe,
            ]
            #expect(fields.allSatisfy { !$0.isEmpty })
        }
        #expect(archive.observations.count == 12)
        #expect(archive.vectors.count == 15)
        #expect(archive.localSolarEclipses.count == 3)
    }

    @Test(
        "JPL geocentric positions",
        arguments: IndependentReferenceArchive.shared.observations.filter {
            $0.series != "mercury-station"
        })
    func jplGeocentricObservation(reference: IndependentReferenceArchive.Observation) throws {
        let body = body(named: reference.body)
        let time = IndependentReferenceDate.civil(reference.utc)
        let equatorial = try body.equatorial(
            at: time, from: .geocentric, equatorDate: .j2000, aberration: .corrected)
        let angularError = IndependentReferenceMath.angularSeparationArcminutes(
            raDegrees1: equatorial.rightAscension * 15, decDegrees1: equatorial.declination,
            raDegrees2: reference.rightAscensionDegrees, decDegrees2: reference.declinationDegrees)
        #expect(
            angularError <= reference.angularToleranceArcminutes,
            "\(reference.body) at \(reference.utc): \(angularError) arcmin")
        let ecliptic = try body.geocentricEclipticState(at: time)
        #expect(
            abs(
                IndependentReferenceMath.wrappedDifference(
                    ecliptic.longitude, reference.eclipticLongitudeDegrees)) * 60
                <= reference.angularToleranceArcminutes)
        #expect(
            abs(ecliptic.latitude - reference.eclipticLatitudeDegrees) * 60
                <= reference.angularToleranceArcminutes)
    }

    @Test(
        "JPL apparent range diagnostics",
        arguments: IndependentReferenceArchive.shared.observations)
    func jplApparentRangeDiagnostic(reference: IndependentReferenceArchive.Observation) throws {
        let time = IndependentReferenceDate.universal(
            reference.utc, deltaTModel: .jplHorizons)
        let equatorial = try body(named: reference.body).equatorial(
            at: time, from: .geocentric, equatorDate: .j2000, aberration: .none)
        let absoluteDifferenceAU = abs(equatorial.distance - reference.apparentRangeAU)

        #expect(reference.apparentRangeAU > 0)
        #expect(
            absoluteDifferenceAU.isFinite,
            "unbounded apparent-range diagnostic difference: \(absoluteDifferenceAU) AU")
    }

    @Test("Mercury station bracket preserves sampled motion and reversal")
    func mercuryStation() throws {
        let references = archive.observations.filter { $0.series == "mercury-station" }.sorted {
            $0.utc < $1.utc
        }
        #expect(references.count == 3)
        var engineLongitudes: [Double] = []
        for reference in references {
            let state = try CelestialBody.mercury.geocentricEclipticState(
                at: IndependentReferenceDate.civil(reference.utc))
            #expect(
                abs(
                    IndependentReferenceMath.wrappedDifference(
                        state.longitude, reference.eclipticLongitudeDegrees)) * 60
                    <= reference.angularToleranceArcminutes)
            engineLongitudes.append(state.longitude)
        }
        let referenceMotions = zip(references, references.dropFirst()).map {
            IndependentReferenceMath.wrappedDifference(
                $1.eclipticLongitudeDegrees, $0.eclipticLongitudeDegrees)
        }
        let engineMotions = zip(engineLongitudes, engineLongitudes.dropFirst()).map {
            IndependentReferenceMath.wrappedDifference($1, $0)
        }
        for index in referenceMotions.indices {
            let derivedEndpointBound = 2 * references[index].angularToleranceArcminutes / 60
            #expect(abs(engineMotions[index] - referenceMotions[index]) <= derivedEndpointBound)
        }
        #expect(referenceMotions[0] * referenceMotions[1] < 0)
        #expect(engineMotions[0] * engineMotions[1] < 0)
    }

    @Test(
        "JPL Chiron heliocentric positions",
        arguments: IndependentReferenceArchive.shared.vectors.filter { $0.body == "chiron" })
    func chironPosition(reference: IndependentReferenceArchive.Vector) throws {
        let position = try Chiron.heliocentricPosition(
            at: IndependentReferenceDate.terrestrial(julianDateTDB: reference.julianDateTDB))
        let error = IndependentReferenceMath.maximumComponentError(
            actual: position, expected: reference.positionAU)
        #expect(
            error <= reference.sanityToleranceAU!,
            "actual ICRF AU vector: [\(position.x), \(position.y), \(position.z)]")
    }

    @Test(
        "JPL Galilean moon state observations",
        arguments: IndependentReferenceArchive.shared.vectors.filter { $0.origin == "jupiter" })
    func galileanMoonStateObservation(reference: IndependentReferenceArchive.Vector) throws {
        let errors = try galileanMoonErrors(reference: reference)
        #expect(errors.position.isFinite)
        #expect(errors.velocity.isFinite)
    }

    @Test(
        "JPL Galilean moon states inside the sourced comparison domain",
        arguments: IndependentReferenceArchive.shared.vectors.filter {
            $0.origin == "jupiter" && $0.relativeTolerance != nil
        })
    func boundedGalileanMoonState(reference: IndependentReferenceArchive.Vector) throws {
        let errors = try galileanMoonErrors(reference: reference)
        let relativeTolerance = try #require(reference.relativeTolerance)
        #expect(errors.position <= relativeTolerance)
        #expect(errors.velocity <= relativeTolerance)
    }

    private func galileanMoonErrors(
        reference: IndependentReferenceArchive.Vector
    ) throws -> (
        position: Double, velocity: Double
    ) {
        let moons = try Jupiter.moons(
            at: IndependentReferenceDate.terrestrial(julianDateTDB: reference.julianDateTDB))
        let state: StateVector =
            switch reference.body {
            case "io": moons.io
            case "europa": moons.europa
            case "ganymede": moons.ganymede
            case "callisto": moons.callisto
            default: fatalError("unexpected Galilean moon \(reference.body)")
            }
        let positionError = IndependentReferenceMath.relativeVectorError(
            actual: state.position, expected: reference.positionAU)
        let velocityError = IndependentReferenceMath.relativeVectorError(
            actual: state.velocity, expected: reference.velocityAUPerDay)
        return (positionError, velocityError)
    }

    @Test("Published seasonal events", arguments: IndependentReferenceArchive.shared.seasons)
    func seasonalEvent(reference: IndependentReferenceArchive.Season) throws {
        let expected = IndependentReferenceDate.civil(reference.utc)
        let year = Calendar(identifier: .gregorian).component(.year, from: expected.date)
        let seasons = try Seasons.forYear(year)
        let actual: AstroTime =
            switch reference.event {
            case "marchEquinox": seasons.marchEquinox
            case "juneSolstice": seasons.juneSolstice
            case "septemberEquinox": seasons.septemberEquinox
            case "decemberSolstice": seasons.decemberSolstice
            default: fatalError("unexpected season \(reference.event)")
            }
        #expect(IndependentReferenceDate.seconds(actual, expected) <= reference.toleranceSeconds)
    }

    @Test("Published lunar quarters", arguments: IndependentReferenceArchive.shared.lunarPhases)
    func lunarQuarter(reference: IndependentReferenceArchive.LunarPhase) throws {
        let expected = IndependentReferenceDate.universal(reference.sourceTime, deltaTModel: .espenakMeeus)
        let actual = try Moon.searchQuarter(after: expected.addingDays(-2))
        let phase: MoonPhase =
            switch reference.phase {
            case "new": .new
            case "firstQuarter": .firstQuarter
            case "full": .full
            case "lastQuarter": .thirdQuarter
            default: fatalError("unexpected phase \(reference.phase)")
            }
        #expect(actual.phase == phase)
        let error = IndependentReferenceDate.terrestrialSeconds(actual.time, expected)
        #expect(error <= reference.toleranceSeconds)
        if reference.sourceTime == "2100-01-18T12:35:00.000Z" {
            let civilTime = IndependentReferenceDate.civil(reference.sourceTime)
            #expect(IndependentReferenceDate.seconds(actual.time, civilTime).isFinite)
        }
    }

    @Test("Archived lunar coordinates use their specified Delta T model")
    func lunarReferenceDateUsesSpecifiedDeltaTModel() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2100-01-18T12:35:00Z"))
        let time = IndependentReferenceDate.universal(
            "2100-01-18T12:35:00.000Z", deltaTModel: .jplHorizons)
        let expectedUT = AstroTime.civilDays(of: date)
        let expectedTT = expectedUT + AstronomyConfig.deltaTJplHorizons(universalTime: expectedUT) / 86_400
        #expect(time.universalTime == expectedUT)
        #expect(time.terrestrialTime == expectedTT)
        #expect(time.deltaTModel == .jplHorizons)
    }

    @Test(
        "Published lunar node events and positions",
        arguments: IndependentReferenceArchive.shared.lunarNodes)
    func lunarNode(reference: IndependentReferenceArchive.LunarNode) throws {
        let expected = IndependentReferenceDate.civil(reference.utc)
        let actual = try Moon.searchNode(after: expected.addingDays(-5))
        #expect(actual.kind == (reference.kind == "ascending" ? .ascending : .descending))
        #expect(
            IndependentReferenceDate.seconds(actual.time, expected) <= reference.timeToleranceSeconds)
        let equatorial = try CelestialBody.moon.equatorial(
            at: expected, from: .geocentric, equatorDate: .ofDate)
        let positionError = IndependentReferenceMath.angularSeparationArcminutes(
            raDegrees1: equatorial.rightAscension * 15, decDegrees1: equatorial.declination,
            raDegrees2: reference.rightAscensionHours * 15, decDegrees2: reference.declinationDegrees)
        #expect(positionError <= reference.positionToleranceArcminutes)
    }

    @Test("Published lunar apsides", arguments: IndependentReferenceArchive.shared.lunarApsides)
    func lunarApsis(reference: IndependentReferenceArchive.Apsis) throws {
        let expected = IndependentReferenceDate.civil(reference.utc)
        let actual = try Moon.searchApsis(after: expected.addingDays(-5))
        #expect(actual.kind == (try apsisKind(named: reference.kind)))
        #expect(
            IndependentReferenceDate.seconds(actual.time, expected) <= reference.timeToleranceSeconds)
        #expect(abs(actual.distanceKM - reference.distanceKM!) <= reference.distanceToleranceKM!)
    }

    @Test("Malformed fixture enum labels are rejected")
    func malformedFixtureEnumLabelsAreRejected() {
        #expect(throws: FixtureLabelError.self) {
            _ = try apsisKind(named: "not-an-apsis")
        }
        #expect(throws: FixtureLabelError.self) {
            _ = try riseSetDirection(named: "not-a-direction")
        }
    }

    @Test("Published Earth apsides", arguments: IndependentReferenceArchive.shared.earthApsides)
    func earthApsis(reference: IndependentReferenceArchive.Apsis) throws {
        let expected = IndependentReferenceDate.civil(reference.utc)
        let actual = try CelestialBody.earth.searchApsis(after: expected.addingDays(-5))
        #expect(actual.kind == (try apsisKind(named: reference.kind)))
        #expect(
            IndependentReferenceDate.seconds(actual.time, expected) <= reference.timeToleranceSeconds)
        #expect(abs(actual.distanceAU - reference.distanceAU!) <= reference.distanceToleranceAU!)
    }

    @Test("USNO rise and set events", arguments: IndependentReferenceArchive.shared.riseSet)
    func riseSet(reference: IndependentReferenceArchive.RiseSet) throws {
        let expected = IndependentReferenceDate.civil(reference.utc)
        let observer = Observer(
            latitude: reference.latitudeDegrees, longitude: reference.longitudeDegrees)
        let direction = try riseSetDirection(named: reference.direction)
        let result = try body(named: reference.body).searchRiseSet(
            direction: direction, after: expected.addingDays(-0.5), from: observer, limitDays: 370)
        let actual = try #require(result)
        #expect(IndependentReferenceDate.seconds(actual, expected) <= reference.timeToleranceSeconds)
    }

    @Test("Published lunar eclipses", arguments: IndependentReferenceArchive.shared.lunarEclipses)
    func lunarEclipse(reference: IndependentReferenceArchive.LunarEclipse) throws {
        let expected = IndependentReferenceDate.universal(reference.universalTime, deltaTModel: .espenakMeeus)
        let actual = try Eclipse.searchLunar(after: expected.addingDays(-10))
        let peakError = IndependentReferenceDate.universalSeconds(actual.peak, expected)
        #expect(peakError <= reference.toleranceSeconds)
        if reference.universalTime == "2099-04-05T08:27Z" {
            let civilTime = IndependentReferenceDate.civil(reference.universalTime)
            #expect(IndependentReferenceDate.seconds(actual.peak, civilTime).isFinite)
        }
        #expect(
            abs(actual.partialDuration - reference.partialSemiDurationMinutes)
                <= reference.durationToleranceMinutes)
        #expect(
            abs(actual.totalDuration - reference.totalSemiDurationMinutes)
                <= reference.durationToleranceMinutes)
    }

    @Test(
        "NASA global solar eclipse peaks",
        arguments: IndependentReferenceArchive.shared.globalSolarEclipses)
    func globalSolarEclipse(reference: IndependentReferenceArchive.GlobalSolarEclipse) throws {
        let expected = IndependentReferenceDate.terrestrialCalendar(reference.terrestrialTime)
        let actual = try Eclipse.searchGlobalSolar(after: expected.addingDays(-10))
        #expect(actual.kind == eclipseKind(named: reference.kind))
        #expect(
            IndependentReferenceDate.seconds(actual.peak, expected) <= reference.timeToleranceSeconds)
        let locationError = IndependentReferenceMath.sphericalDistanceDegrees(
            latitude1: try #require(actual.latitude), longitude1: try #require(actual.longitude),
            latitude2: reference.latitudeDegrees, longitude2: reference.longitudeDegrees)
        #expect(locationError <= reference.locationToleranceDegrees)
    }

    @Test(
        "Published local solar eclipse contacts",
        arguments: IndependentReferenceArchive.shared.localSolarEclipses)
    func localSolarEclipse(reference: IndependentReferenceArchive.LocalSolarEclipse) throws {
        let expectedPeak = IndependentReferenceDate.civil(reference.peakUTC)
        let observer = Observer(
            latitude: reference.latitudeDegrees, longitude: reference.longitudeDegrees)
        let actual = try Eclipse.searchLocalSolar(after: expectedPeak.addingDays(-10), from: observer)
        #expect(actual.kind == eclipseKind(named: reference.kind))
        expectEvent(
            actual.partialBegin, utc: reference.partialBeginUTC,
            altitude: reference.partialBeginAltitudeDegrees, reference: reference)
        expectEvent(
            actual.peak, utc: reference.peakUTC, altitude: reference.peakAltitudeDegrees,
            reference: reference)
        expectEvent(
            actual.partialEnd, utc: reference.partialEndUTC,
            altitude: reference.partialEndAltitudeDegrees, reference: reference)
        if let utc = reference.totalBeginUTC, let altitude = reference.totalBeginAltitudeDegrees {
            expectEvent(
                try #require(actual.totalBegin), utc: utc, altitude: altitude, reference: reference)
        } else {
            #expect(actual.totalBegin == nil)
        }
        if let utc = reference.totalEndUTC, let altitude = reference.totalEndAltitudeDegrees {
            expectEvent(try #require(actual.totalEnd), utc: utc, altitude: altitude, reference: reference)
        } else {
            #expect(actual.totalEnd == nil)
        }
    }

    @Test("NASA planetary transit contacts", arguments: IndependentReferenceArchive.shared.transits)
    func planetaryTransit(reference: IndependentReferenceArchive.Transit) throws {
        let expectedPeak = IndependentReferenceDate.civil(reference.peakUTC)
        let actual = try Transit.search(
            body: body(named: reference.body), after: expectedPeak.addingDays(-100))
        #expect(
            IndependentReferenceDate.seconds(
                actual.start, IndependentReferenceDate.civil(reference.startUTC))
                <= reference.timeToleranceSeconds)
        #expect(
            IndependentReferenceDate.seconds(actual.peak, expectedPeak) <= reference.timeToleranceSeconds)
        #expect(
            IndependentReferenceDate.seconds(
                actual.finish, IndependentReferenceDate.civil(reference.finishUTC))
                <= reference.timeToleranceSeconds)
        #expect(
            abs(actual.separation - reference.separationArcminutes)
                <= reference.separationToleranceArcminutes)
    }

    @Test("Frame mutation exceeds the archived position tolerance")
    func frameMutationFails() throws {
        let reference = try #require(archive.observations.first { $0.body == "mars" })
        let time = IndependentReferenceDate.civil(reference.utc)
        let correct = try CelestialBody.mars.equatorial(
            at: time, from: .geocentric, equatorDate: .j2000, aberration: .corrected)
        let wrongFrame = try CelestialBody.mars.equatorial(
            at: time, from: .geocentric, equatorDate: .ofDate, aberration: .corrected)
        let correctError = IndependentReferenceMath.angularSeparationArcminutes(
            raDegrees1: correct.rightAscension * 15, decDegrees1: correct.declination,
            raDegrees2: reference.rightAscensionDegrees, decDegrees2: reference.declinationDegrees)
        let mutatedError = IndependentReferenceMath.angularSeparationArcminutes(
            raDegrees1: wrongFrame.rightAscension * 15, decDegrees1: wrongFrame.declination,
            raDegrees2: reference.rightAscensionDegrees, decDegrees2: reference.declinationDegrees)
        #expect(correctError <= reference.angularToleranceArcminutes)
        #expect(mutatedError > reference.angularToleranceArcminutes)
    }

    @Test("Civil UTC mutation exceeds the source-compatible event tolerance")
    func timeScaleMutationFails() throws {
        let reference = try #require(
            archive.lunarPhases.first { $0.sourceTime == "2100-01-18T12:35:00.000Z" })
        let expected = IndependentReferenceDate.universal(reference.sourceTime, deltaTModel: .espenakMeeus)
        let correct = try Moon.searchQuarter(after: expected.addingDays(-2))
        let misreadAsCivil = IndependentReferenceDate.civil(reference.sourceTime)
        #expect(
            IndependentReferenceDate.terrestrialSeconds(correct.time, expected)
                <= reference.toleranceSeconds)
        #expect(
            IndependentReferenceDate.seconds(correct.time, misreadAsCivil)
                > reference.toleranceSeconds)
    }

    @Test("Sign and unit mutations exceed archived tolerances")
    func signAndUnitMutationsFail() throws {
        let vector = try #require(
            archive.vectors.first { $0.body == "chiron" && $0.julianDateTDB == 2_451_544.5 })
        let actualVector = try Chiron.heliocentricPosition(
            at: IndependentReferenceDate.terrestrial(julianDateTDB: vector.julianDateTDB))
        var signMutated = vector.positionAU
        signMutated[0] *= -1
        #expect(
            IndependentReferenceMath.maximumComponentError(
                actual: actualVector, expected: vector.positionAU) <= vector.sanityToleranceAU!)
        #expect(
            IndependentReferenceMath.maximumComponentError(actual: actualVector, expected: signMutated)
                > vector.sanityToleranceAU!)
        let apsis = archive.earthApsides[0]
        let actualApsis = try CelestialBody.earth.searchApsis(
            after: IndependentReferenceDate.civil(apsis.utc).addingDays(-5))
        #expect(abs(actualApsis.distanceAU - apsis.distanceAU!) <= apsis.distanceToleranceAU!)
        #expect(
            abs(actualApsis.distanceAU - apsis.distanceAU! * 149_597_870.7) > apsis.distanceToleranceAU!)
    }

    @Test("Event-selection mutation exceeds the archived phase tolerance")
    func eventSelectionMutationFails() throws {
        let reference = archive.lunarPhases[0]
        let expected = IndependentReferenceDate.universal(reference.sourceTime, deltaTModel: .espenakMeeus)
        let correct = try Moon.searchQuarter(after: expected.addingDays(-2))
        let wrong = try Moon.nextQuarter(after: correct)
        #expect(
            IndependentReferenceDate.terrestrialSeconds(correct.time, expected)
                <= reference.toleranceSeconds)
        #expect(
            IndependentReferenceDate.terrestrialSeconds(wrong.time, expected)
                > reference.toleranceSeconds)
        #expect(wrong.phase != correct.phase)
    }

    private func body(named name: String) -> CelestialBody {
        switch name {
        case "sun": .sun
        case "moon": .moon
        case "mercury": .mercury
        case "mars": .mars
        case "pluto": .pluto
        case "venus": .venus
        default: fatalError("unexpected body \(name)")
        }
    }

    private func apsisKind(named name: String) throws -> ApsisKind {
        switch name {
        case "pericenter": .pericenter
        case "apocenter": .apocenter
        default: throw FixtureLabelError.unknownApsisKind(name)
        }
    }

    private func riseSetDirection(named name: String) throws -> RiseSetDirection {
        switch name {
        case "rise": .rise
        case "set": .set
        default: throw FixtureLabelError.unknownRiseSetDirection(name)
        }
    }

    private func eclipseKind(named name: String) -> EclipseKind {
        switch name {
        case "partial": .partial
        case "annular": .annular
        case "total": .total
        default: fatalError("unexpected eclipse kind \(name)")
        }
    }

    private func expectEvent(
        _ actual: EclipseEvent, utc: String, altitude: Double,
        reference: IndependentReferenceArchive.LocalSolarEclipse
    ) {
        #expect(
            IndependentReferenceDate.seconds(actual.time, IndependentReferenceDate.civil(utc))
                <= reference.timeToleranceSeconds)
        if altitude >= 0 {
            #expect(abs(actual.altitude - altitude) <= reference.altitudeToleranceDegrees)
        }
    }
}
