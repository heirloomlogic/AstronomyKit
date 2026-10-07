//
//  EngineFrameRotations.swift
//  AstronomyKit
//
//  Rotations between the engine's reference frames.
//

import Foundation

extension Engine {
    /// The rotations between reference frames, one for each frame pair the C
    /// engine provides. Each reverse rotation is the transpose of its forward
    /// rotation. Rotations at a time read nutation through the shared cache.
    enum FrameRotation {}
}

extension Engine.FrameRotation {
    typealias Rotation = Engine.Rotation
    typealias EQJ = Engine.EQJ
    typealias EQD = Engine.EQD
    typealias ECL = Engine.ECL
    typealias ECT = Engine.ECT
    typealias HOR = Engine.HOR
    typealias GAL = Engine.GAL

    // MARK: Ecliptic

    /// R1(ε0): from the J2000 equator to the J2000 mean ecliptic, with the
    /// IAU 2006 obliquity ε0 = 84,381.406″ (Capitaine, Wallace and Chapront 2003).
    static let eqjToEcl: Rotation<EQJ, ECL> = tilted(by: Engine.Precession.obliquityAtJ2000 / 3600)

    static let eclToEqj: Rotation<ECL, EQJ> = eqjToEcl.inverse

    /// R1(εA + Δε): from the true equator of date to the true ecliptic of
    /// date.
    static func eqdToEct(_ time: Engine.Time) -> Rotation<EQD, ECT> {
        tilted(by: Engine.EarthTilt(tt: time.tt).trueObliquity)
    }

    static func ectToEqd(_ time: Engine.Time) -> Rotation<ECT, EQD> { eqdToEct(time).inverse }

    /// The rotation about the x axis that carries an equator onto an ecliptic
    /// tilted `obliquity` degrees from it.
    private static func tilted<From, To>(by obliquity: Double) -> Rotation<From, To> {
        let radians = obliquity * Engine.radiansPerDegree
        let c = cos(radians)
        let s = sin(radians)
        return Rotation(rot: ((1, 0, 0), (0, c, -s), (0, s, c)))
    }

    // MARK: Precession and nutation

    /// Precession then nutation: from the J2000 equator to the true equator
    /// of date.
    static func eqjToEqd(_ time: Engine.Time) -> Rotation<EQJ, EQD> {
        eqjToEqd(tt: time.tt, tilt: Engine.EarthTilt(tt: time.tt))
    }

    private static func eqjToEqd(tt: Double, tilt: Engine.EarthTilt) -> Rotation<EQJ, EQD> {
        Engine.Precession.rotation(tt: tt).then(tilt.nutationRotation)
    }

    static func eqdToEqj(_ time: Engine.Time) -> Rotation<EQD, EQJ> { eqjToEqd(time).inverse }

    static func eqjToEct(_ time: Engine.Time) -> Rotation<EQJ, ECT> {
        let tilt = Engine.EarthTilt(tt: time.tt)
        return eqjToEqd(tt: time.tt, tilt: tilt).then(tilted(by: tilt.trueObliquity))
    }

    static func ectToEqj(_ time: Engine.Time) -> Rotation<ECT, EQJ> { eqjToEct(time).inverse }

    static func eqdToEcl(_ time: Engine.Time) -> Rotation<EQD, ECL> { eqdToEqj(time).then(eqjToEcl) }

    static func eclToEqd(_ time: Engine.Time) -> Rotation<ECL, EQD> { eqdToEcl(time).inverse }

    // MARK: Horizon

    /// From the true equator of date to the horizon of `observer`: x north,
    /// y west, z zenith. Uses the observer's latitude and longitude, not its
    /// height, and apparent sidereal time at `time`. The public layer
    /// validates the observer.
    static func eqdToHor(_ time: Engine.Time, observer: Observer) -> Rotation<EQD, HOR> {
        let latitude = observer.latitude * Engine.radiansPerDegree
        let longitude = observer.longitude * Engine.radiansPerDegree
        let (sinLat, cosLat) = (sin(latitude), cos(latitude))
        let (sinLon, cosLon) = (sin(longitude), cos(longitude))
        // Zenith, north and west in Earth-fixed axes, then turned by sidereal
        // time into the equator of date.
        let spin = -15 * Engine.EarthRotation.apparentSiderealTime(time) * Engine.radiansPerDegree
        let (c, s) = (cos(spin), sin(spin))
        func turned(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
            (c * v.0 + s * v.1, -s * v.0 + c * v.1, v.2)
        }
        let zenith = turned((cosLat * cosLon, cosLat * sinLon, sinLat))
        let north = turned((-sinLat * cosLon, -sinLat * sinLon, cosLat))
        let west = turned((sinLon, -cosLon, 0))
        // Element (i, j) of the matrix is rot[j][i]: rot[i] is EQD axis i
        // expressed in HOR.
        return Rotation(
            rot: (
                (north.0, west.0, zenith.0),
                (north.1, west.1, zenith.1),
                (north.2, west.2, zenith.2)
            )
        )
    }

    static func horToEqd(_ time: Engine.Time, observer: Observer) -> Rotation<HOR, EQD> {
        eqdToHor(time, observer: observer).inverse
    }

    static func eqjToHor(_ time: Engine.Time, observer: Observer) -> Rotation<EQJ, HOR> {
        eqjToEqd(time).then(eqdToHor(time, observer: observer))
    }

    static func horToEqj(_ time: Engine.Time, observer: Observer) -> Rotation<HOR, EQJ> {
        eqjToHor(time, observer: observer).inverse
    }

    static func eclToHor(_ time: Engine.Time, observer: Observer) -> Rotation<ECL, HOR> {
        eclToEqd(time).then(eqdToHor(time, observer: observer))
    }

    static func horToEcl(_ time: Engine.Time, observer: Observer) -> Rotation<HOR, ECL> {
        eclToHor(time, observer: observer).inverse
    }

    // MARK: Galactic

    /// The J2000 galactic axes of the Hipparcos Catalogue (ESA 1997, Vol. 1,
    /// §1.5.3), following Murray (1989): north galactic pole at
    /// αG = 192.85948°, δG = +27.12825°, and the galactic plane's ascending
    /// node on the J2000 equator at galactic longitude lΩ = 32.93192°. The
    /// matrix is Rz(−lΩ)·Rx(90° − δG)·Rz(αG + 90°), applied to J2000 vectors.
    static let eqjToGal: Rotation<EQJ, GAL> = {
        // A pivot turns vectors, so each axis rotation above is a pivot by
        // the opposite angle.
        let axes = Rotation<EQJ, EQJ>.identity
            .turned(axis: 2, degrees: -(192.859_48 + 90))
            .turned(axis: 0, degrees: -(90 - 27.128_25))
            .turned(axis: 2, degrees: 32.931_92)
        return Rotation(rot: axes.rot)
    }()

    static let galToEqj: Rotation<GAL, EQJ> = eqjToGal.inverse
}
