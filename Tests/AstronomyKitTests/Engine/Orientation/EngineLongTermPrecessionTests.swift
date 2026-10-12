import Foundation
import Testing

@testable import AstronomyKit

@Suite("Long-term precession")
struct EngineLongTermPrecessionTests {
    @Test("ERFA published eraLtp matrix at Julian epoch 1666.666")
    func publishedMatrix() {
        let expected = [
            [0.9967044141159213819, 0.7437801893193210840e-1, 0.3237624409345603401e-1],
            [-0.7437802731819618167e-1, 0.9972293894454533070, -0.1205768842723593346e-2],
            [-0.3237622482766575399e-1, -0.1206286039697609008e-2, 0.9994750246704010914],
        ]
        let actual = PublishedOrientation.matrix(Engine.Precession.rotation(tt: (1666.666 - 2000) * 365.25))
        #expect(PublishedOrientation.maximumDifference(actual, expected) <= 1e-14)
    }

    @Test("ERFA published far-epoch poles; internal model only")
    func publishedPoles() {
        let equator = PublishedOrientation.matrix(Engine.Precession.rotation(tt: (-2500 - 2000) * 365.25))[2]
        let expectedEquator = [-0.3586652560237326659, -0.1996978910771128475, 0.9118552442250819624]
        #expect(PublishedOrientation.maximumDifference([equator], [expectedEquator]) <= 1e-14)
        let tt = (-1500 - 2000) * 365.25
        let matrix = PublishedOrientation.matrix(Engine.Precession.rotation(tt: tt))
        let epsilon = Engine.Precession.meanObliquity(tt: tt) * Engine.radiansPerDegree
        let ecliptic = (0..<3).map { cos(epsilon) * matrix[2][$0] - sin(epsilon) * matrix[1][$0] }
        let expectedEcliptic = [0.0004768625676477096525, -0.4052259533091875112, 0.9142164401096448012]
        #expect(PublishedOrientation.maximumDifference([ecliptic], [expectedEcliptic]) <= 1e-14)
    }

    @Test(
        "Public date-frame routes use long-term precession throughout the accepted interval",
        arguments: PublishedLongTermPrecession.references, [DeltaTModel.espenakMeeus, .jplHorizons])
    func publicRoutes(reference: PublishedLongTermPrecession.Reference, model: DeltaTModel) throws {
        let time = AstroTime(tt: reference.tt, ut: reference.tt, deltaTModel: model)
        let native = time.engine
        let nutation = PublishedOrientation.matrix(Engine.EarthTilt(tt: reference.tt).nutationRotation)
        let equator = PublishedOrientation.product(nutation, reference.matrix)
        let tilt = PublishedOrientation.r1(Engine.EarthTilt(tt: reference.tt).trueObliquity * Engine.radiansPerDegree)
        let ecliptic = PublishedOrientation.product(tilt, equator)
        let checks: [(RotationMatrix, [[Double]])] = [
            (try .equatorialJ2000ToEquatorialOfDate(at: time), equator),
            (try .equatorialOfDateToEquatorialJ2000(at: time), PublishedOrientation.transposed(equator)),
            (try .equatorialJ2000ToEclipticOfDate(at: time), ecliptic),
            (try .eclipticOfDateToEquatorialJ2000(at: time), PublishedOrientation.transposed(ecliptic)),
        ]
        for (rotation, expected) in checks {
            #expect(
                PublishedOrientation.maximumDifference(NativeCoordinateFacadeTests.matrix(rotation), expected) <= 2e-15)
        }
        let observer = Observer(latitude: 35.6, longitude: -82.55, height: 650)
        let horizon = PublishedOrientation.matrix(Engine.FrameRotation.eqdToHor(native, observer: observer))
        let publicHorizon = try RotationMatrix.equatorialJ2000ToHorizon(at: time, from: observer)
        #expect(
            PublishedOrientation.maximumDifference(
                NativeCoordinateFacadeTests.matrix(publicHorizon), PublishedOrientation.product(horizon, equator))
                <= 2e-15)
        let state = try observer.state(at: time, equator: .j2000)
        #expect(
            [
                state.position.x, state.position.y, state.position.z, state.velocity.x, state.velocity.y,
                state.velocity.z,
            ].allSatisfy { $0.isFinite })
        #expect(state.time.terrestrialTime == reference.tt)
    }

    @Test("Nonfinite rotation inputs propagate invalid elements")
    func nonfinite() throws {
        for value in [Double.nan, .infinity, -.infinity] {
            let time = AstroTime(tt: value, ut: 0, deltaTModel: .espenakMeeus)
            let rotation = try RotationMatrix.equatorialJ2000ToEquatorialOfDate(at: time)
            #expect(NativeCoordinateFacadeTests.matrix(rotation).flatMap { $0 }.allSatisfy { $0.isNaN })
        }
    }
}
