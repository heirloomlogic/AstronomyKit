//
//  Rotation.swift
//  AstronomyKit
//
//  Coordinate system rotation matrices.
//

// MARK: - Rotation Matrix

/// A 3x3 rotation matrix for coordinate system transformations.
///
/// Rotation matrices are used to convert vectors between different
/// celestial coordinate systems: equatorial (J2000 and of-date),
/// ecliptic, horizontal, and galactic.
///
/// ## Example
///
/// ```swift
/// // Convert from J2000 equatorial to ecliptic coordinates
/// let rotation = try RotationMatrix.equatorialJ2000ToEcliptic()
/// let ecliptic = position.rotated(by: rotation)
/// ```
public struct RotationMatrix: Sendable {
    /// The public matrix carries no frame type; its elements stay inline.
    enum Frame: Engine.Frame {}
    let storage: Engine.Rotation<Frame, Frame>

    /// Access matrix element at row, column.
    ///
    /// Traps on an out-of-range index.
    public subscript(row: Int, col: Int) -> Double {
        storage[row, col]
    }

    /// Creates a rotation matrix with the elements of a native engine rotation.
    init<From, To>(_ rotation: Engine.Rotation<From, To>) {
        storage = Engine.Rotation(rot: rotation.rot)
    }
}

// MARK: - Matrix Operations

extension RotationMatrix {
    /// The identity rotation matrix (no rotation).
    public static let identity = RotationMatrix(Engine.Rotation<Frame, Frame>.identity)

    /// Returns the inverse (transpose) of this rotation.
    ///
    /// For rotation matrices, the inverse equals the transpose.
    public var inverse: RotationMatrix {
        get throws {
            RotationMatrix(storage.inverse)
        }
    }

    /// Combines this rotation with another.
    ///
    /// The resulting rotation applies `self` first, then `other`.
    ///
    /// - Parameter other: The rotation to apply after this one.
    /// - Returns: The combined rotation matrix.
    /// - Throws: `AstronomyError` if the combination fails.
    public func combined(with other: RotationMatrix) throws -> RotationMatrix {
        RotationMatrix(storage.then(other.storage))
    }

    /// Creates a rotation that pivots around an axis.
    ///
    /// - Parameters:
    ///   - axis: The axis to rotate around (0=x, 1=y, 2=z).
    ///   - angle: The rotation angle in degrees.
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the pivot fails.
    public static func pivot(axis: Int, angle: Double) throws -> RotationMatrix {
        RotationMatrix(try identity.storage.pivoted(axis: axis, angle: angle))
    }
}

// MARK: - Coordinate System Conversions

extension RotationMatrix {
    // MARK: Equatorial J2000 (EQJ) conversions

    /// Creates a rotation from J2000 equatorial to ecliptic coordinates.
    public static func equatorialJ2000ToEcliptic() throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.eqjToEcl)
    }

    /// Creates a rotation from ecliptic to J2000 equatorial coordinates.
    public static func eclipticToEquatorialJ2000() throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.eclToEqj)
    }

    /// Creates a rotation from J2000 equatorial to equatorial-of-date coordinates.
    ///
    /// - Parameter time: The time for the of-date frame.
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the rotation cannot be computed.
    public static func equatorialJ2000ToEquatorialOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.eqjToEqd(time.coordinateTime))
    }

    /// Creates a rotation from equatorial-of-date to J2000 equatorial coordinates.
    ///
    /// - Parameter time: The time for the of-date frame.
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the rotation cannot be computed.
    public static func equatorialOfDateToEquatorialJ2000(
        at time: AstroTime
    ) throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.eqdToEqj(time.coordinateTime))
    }

    /// Creates a rotation from J2000 equatorial to horizontal coordinates.
    ///
    /// - Parameters:
    ///   - time: The observation time.
    ///   - observer: The geographic observer location.
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the rotation cannot be computed.
    public static func equatorialJ2000ToHorizon(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        try observer.validate()
        return RotationMatrix(Engine.FrameRotation.eqjToHor(time.coordinateTime, observer: observer))
    }

    /// Creates a rotation from horizontal to J2000 equatorial coordinates.
    ///
    /// - Parameters:
    ///   - time: The observation time.
    ///   - observer: The geographic observer location.
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the rotation cannot be computed.
    public static func horizonToEquatorialJ2000(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        try observer.validate()
        return RotationMatrix(Engine.FrameRotation.horToEqj(time.coordinateTime, observer: observer))
    }

    /// Creates a rotation from J2000 equatorial to galactic coordinates.
    ///
    /// The galactic axes are the J2000 axes of the Hipparcos Catalogue (ESA
    /// 1997, Vol. 1, §1.5.3; Murray 1989): north galactic pole at right
    /// ascension 192.85948° and declination +27.12825°, with the north
    /// celestial pole at galactic longitude 122.93192°. Never throws.
    public static func equatorialJ2000ToGalactic() throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.eqjToGal)
    }

    /// Creates a rotation from galactic to J2000 equatorial coordinates: the
    /// inverse of ``equatorialJ2000ToGalactic()``. Never throws.
    public static func galacticToEquatorialJ2000() throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.galToEqj)
    }

    // MARK: Ecliptic (ECL) conversions

    /// Creates a rotation from ecliptic to horizontal coordinates.
    public static func eclipticToHorizon(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        try observer.validate()
        return RotationMatrix(Engine.FrameRotation.eclToHor(time.coordinateTime, observer: observer))
    }

    /// Creates a rotation from horizontal to ecliptic coordinates.
    public static func horizonToEcliptic(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        try observer.validate()
        return RotationMatrix(Engine.FrameRotation.horToEcl(time.coordinateTime, observer: observer))
    }

    // MARK: Equatorial of Date (EQD) conversions

    /// Creates a rotation from equatorial-of-date to horizontal coordinates.
    public static func equatorialOfDateToHorizon(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        try observer.validate()
        return RotationMatrix(Engine.FrameRotation.eqdToHor(time.coordinateTime, observer: observer))
    }

    /// Creates a rotation from horizontal to equatorial-of-date coordinates.
    public static func horizonToEquatorialOfDate(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        try observer.validate()
        return RotationMatrix(Engine.FrameRotation.horToEqd(time.coordinateTime, observer: observer))
    }

    /// Creates a rotation from equatorial-of-date to ecliptic coordinates.
    public static func equatorialOfDateToEcliptic(at time: AstroTime) throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.eqdToEcl(time.coordinateTime))
    }

    /// Creates a rotation from ecliptic to equatorial-of-date coordinates.
    public static func eclipticToEquatorialOfDate(at time: AstroTime) throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.eclToEqd(time.coordinateTime))
    }

    // MARK: Ecliptic of Date (ECT) conversions

    /// Creates a rotation from J2000 equatorial to ecliptic-of-date coordinates.
    public static func equatorialJ2000ToEclipticOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.eqjToEct(time.coordinateTime))
    }

    /// Creates a rotation from ecliptic-of-date to J2000 equatorial coordinates.
    public static func eclipticOfDateToEquatorialJ2000(
        at time: AstroTime
    ) throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.ectToEqj(time.coordinateTime))
    }

    /// Creates a rotation from equatorial-of-date to ecliptic-of-date coordinates.
    public static func equatorialOfDateToEclipticOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.eqdToEct(time.coordinateTime))
    }

    /// Creates a rotation from ecliptic-of-date to equatorial-of-date coordinates.
    public static func eclipticOfDateToEquatorialOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        RotationMatrix(Engine.FrameRotation.ectToEqd(time.coordinateTime))
    }
}

// MARK: - Vector Rotation

extension Vector3D {
    /// Applies a rotation matrix to this vector.
    ///
    /// - Parameter rotation: The rotation matrix to apply.
    /// - Returns: The rotated vector.
    /// - Throws: `AstronomyError` if the rotation fails.
    public func rotated(by rotation: RotationMatrix) throws -> Vector3D {
        Vector3D(rotation.storage.apply(to: engineVector(in: RotationMatrix.Frame.self)), at: time)
    }
}

// MARK: - State Vector Rotation

extension StateVector {
    /// Applies a rotation matrix to both the position and velocity vectors.
    ///
    /// - Parameter rotation: The rotation matrix to apply.
    /// - Returns: The rotated state vector.
    /// - Throws: `AstronomyError` if the rotation fails.
    public func rotated(by rotation: RotationMatrix) throws -> StateVector {
        let state = Engine.State<RotationMatrix.Frame>(
            x: position.x, y: position.y, z: position.z,
            vx: velocity.x, vy: velocity.y, vz: velocity.z,
            time: time.coordinateTime
        )
        return StateVector(rotation.storage.apply(to: state), at: time)
    }
}

// MARK: - Equatable

extension RotationMatrix: Equatable {
    /// Two rotation matrices are equal when all nine elements match.
    ///
    /// Written by hand because the inline tuple storage has no synthesized conformance.
    public static func == (lhs: RotationMatrix, rhs: RotationMatrix) -> Bool {
        lhs[0, 0] == rhs[0, 0] && lhs[0, 1] == rhs[0, 1] && lhs[0, 2] == rhs[0, 2]
            && lhs[1, 0] == rhs[1, 0] && lhs[1, 1] == rhs[1, 1] && lhs[1, 2] == rhs[1, 2]
            && lhs[2, 0] == rhs[2, 0] && lhs[2, 1] == rhs[2, 1] && lhs[2, 2] == rhs[2, 2]
    }
}

// MARK: - CustomStringConvertible

extension RotationMatrix: CustomStringConvertible {
    /// A textual representation of the 3×3 rotation matrix.
    public var description: String {
        """
        [\(self[0, 0]), \(self[0, 1]), \(self[0, 2])]
        [\(self[1, 0]), \(self[1, 1]), \(self[1, 2])]
        [\(self[2, 0]), \(self[2, 1]), \(self[2, 2])]
        """
    }
}
