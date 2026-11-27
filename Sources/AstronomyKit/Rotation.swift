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
public struct RotationMatrix: Sendable, Equatable {
    let r00: Double
    let r01: Double
    let r02: Double
    let r10: Double
    let r11: Double
    let r12: Double
    let r20: Double
    let r21: Double
    let r22: Double

    /// Access matrix element at row, column.
    ///
    /// Traps on an out-of-range index.
    public subscript(row: Int, col: Int) -> Double {
        switch (row, col) {
        case (0, 0): return r00
        case (0, 1): return r01
        case (0, 2): return r02
        case (1, 0): return r10
        case (1, 1): return r11
        case (1, 2): return r12
        case (2, 0): return r20
        case (2, 1): return r21
        case (2, 2): return r22
        default: preconditionFailure("RotationMatrix index (\(row), \(col)) out of range")
        }
    }
}

// MARK: - Matrix Operations

extension RotationMatrix {
    /// The identity rotation matrix (no rotation).
    public static var identity: RotationMatrix {
        RotationMatrix(
            r00: 1, r01: 0, r02: 0,
            r10: 0, r11: 1, r12: 0,
            r20: 0, r21: 0, r22: 1
        )
    }

    /// Returns the inverse (transpose) of this rotation.
    ///
    /// For rotation matrices, the inverse equals the transpose.
    public var inverse: RotationMatrix {
        get throws {
            EngineRotation.inverse(self)
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
        EngineRotation.combine(self, other)
    }

    /// Creates a rotation that pivots around an axis.
    ///
    /// - Parameters:
    ///   - axis: The axis to rotate around (0=x, 1=y, 2=z).
    ///   - angle: The rotation angle in degrees.
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the pivot fails.
    public static func pivot(axis: Int, angle: Double) throws -> RotationMatrix {
        try EngineRotation.pivot(.identity, axis: axis, angle: angle)
    }
}

// MARK: - Coordinate System Conversions

extension RotationMatrix {
    // MARK: Equatorial J2000 (EQJ) conversions

    /// Creates a rotation from J2000 equatorial to ecliptic coordinates.
    public static func equatorialJ2000ToEcliptic() throws -> RotationMatrix {
        EngineRotation.eqjToEcl
    }

    /// Creates a rotation from ecliptic to J2000 equatorial coordinates.
    public static func eclipticToEquatorialJ2000() throws -> RotationMatrix {
        EngineRotation.eclToEqj
    }

    /// Creates a rotation from J2000 equatorial to equatorial-of-date coordinates.
    ///
    /// - Parameter time: The time for the of-date frame.
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the rotation cannot be computed.
    public static func equatorialJ2000ToEquatorialOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        EngineRotation.eqjToEqd(at: time)
    }

    /// Creates a rotation from equatorial-of-date to J2000 equatorial coordinates.
    ///
    /// - Parameter time: The time for the of-date frame.
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the rotation cannot be computed.
    public static func equatorialOfDateToEquatorialJ2000(
        at time: AstroTime
    ) throws -> RotationMatrix {
        EngineRotation.eqdToEqj(at: time)
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
        EngineRotation.eqjToHor(at: time, observer: try observer.validated())
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
        EngineRotation.horToEqj(at: time, observer: try observer.validated())
    }

    /// Creates a rotation from J2000 equatorial to galactic coordinates.
    public static func equatorialJ2000ToGalactic() throws -> RotationMatrix {
        EngineRotation.eqjToGal
    }

    /// Creates a rotation from galactic to J2000 equatorial coordinates.
    public static func galacticToEquatorialJ2000() throws -> RotationMatrix {
        EngineRotation.galToEqj
    }

    // MARK: Ecliptic (ECL) conversions

    /// Creates a rotation from ecliptic to horizontal coordinates.
    public static func eclipticToHorizon(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        EngineRotation.eclToHor(at: time, observer: try observer.validated())
    }

    /// Creates a rotation from horizontal to ecliptic coordinates.
    public static func horizonToEcliptic(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        EngineRotation.horToEcl(at: time, observer: try observer.validated())
    }

    // MARK: Equatorial of Date (EQD) conversions

    /// Creates a rotation from equatorial-of-date to horizontal coordinates.
    public static func equatorialOfDateToHorizon(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        EngineRotation.eqdToHor(at: time, observer: try observer.validated())
    }

    /// Creates a rotation from horizontal to equatorial-of-date coordinates.
    public static func horizonToEquatorialOfDate(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        EngineRotation.horToEqd(at: time, observer: try observer.validated())
    }

    /// Creates a rotation from equatorial-of-date to ecliptic coordinates.
    public static func equatorialOfDateToEcliptic(at time: AstroTime) throws -> RotationMatrix {
        EngineRotation.eqdToEcl(at: time)
    }

    /// Creates a rotation from ecliptic to equatorial-of-date coordinates.
    public static func eclipticToEquatorialOfDate(at time: AstroTime) throws -> RotationMatrix {
        EngineRotation.eclToEqd(at: time)
    }

    // MARK: Ecliptic of Date (ECT) conversions

    /// Creates a rotation from J2000 equatorial to ecliptic-of-date coordinates.
    public static func equatorialJ2000ToEclipticOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        EngineRotation.eqjToEct(at: time)
    }

    /// Creates a rotation from ecliptic-of-date to J2000 equatorial coordinates.
    public static func eclipticOfDateToEquatorialJ2000(
        at time: AstroTime
    ) throws -> RotationMatrix {
        EngineRotation.ectToEqj(at: time)
    }

    /// Creates a rotation from equatorial-of-date to ecliptic-of-date coordinates.
    public static func equatorialOfDateToEclipticOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        EngineRotation.eqdToEct(at: time)
    }

    /// Creates a rotation from ecliptic-of-date to equatorial-of-date coordinates.
    public static func eclipticOfDateToEquatorialOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        EngineRotation.ectToEqd(at: time)
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
        EngineRotation.rotateVector(rotation, self)
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
        EngineRotation.rotateState(rotation, self)
    }
}

// MARK: - CustomStringConvertible

extension RotationMatrix: CustomStringConvertible {
    /// A textual representation of the 3×3 rotation matrix.
    public var description: String {
        """
        [\(r00), \(r01), \(r02)]
        [\(r10), \(r11), \(r12)]
        [\(r20), \(r21), \(r22)]
        """
    }
}
