//
//  Rotation.swift
//  AstronomyKit
//
//  Coordinate system rotation matrices.
//

import CLibAstronomy

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
    /// The 3x3 rotation matrix stored as a flat array in row-major order.
    private let matrix: [Double]

    /// Access matrix element at row, column.
    public subscript(row: Int, col: Int) -> Double {
        matrix[row * 3 + col]
    }

    /// Creates a rotation matrix from the C structure.
    internal init(_ raw: astro_rotation_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        // Flatten the 3x3 C array
        self.matrix = [
            raw.rot.0.0, raw.rot.0.1, raw.rot.0.2,
            raw.rot.1.0, raw.rot.1.1, raw.rot.1.2,
            raw.rot.2.0, raw.rot.2.1, raw.rot.2.2,
        ]
    }

    /// Creates a rotation matrix from a flat array (row-major).
    private init(matrix: [Double]) {
        precondition(matrix.count == 9)
        self.matrix = matrix
    }

    /// The internal C representation.
    internal var raw: astro_rotation_t {
        var rot = astro_rotation_t()
        rot.status = ASTRO_SUCCESS
        rot.rot.0 = (matrix[0], matrix[1], matrix[2])
        rot.rot.1 = (matrix[3], matrix[4], matrix[5])
        rot.rot.2 = (matrix[6], matrix[7], matrix[8])
        return rot
    }
}

// MARK: - Matrix Operations

extension RotationMatrix {
    /// The identity rotation matrix (no rotation).
    public static var identity: RotationMatrix {
        RotationMatrix(matrix: [
            1, 0, 0,
            0, 1, 0,
            0, 0, 1,
        ])
    }

    /// Returns the inverse (transpose) of this rotation.
    ///
    /// For rotation matrices, the inverse equals the transpose.
    public var inverse: RotationMatrix {
        get throws {
            let result = Astronomy_InverseRotation(raw)
            return try RotationMatrix(result)
        }
    }

    /// Combines this rotation with another.
    ///
    /// The resulting rotation applies `self` first, then `other`.
    ///
    /// - Parameter other: The rotation to apply after this one.
    /// - Returns: The combined rotation matrix.
    public func combined(with other: RotationMatrix) throws -> RotationMatrix {
        let result = Astronomy_CombineRotation(self.raw, other.raw)
        return try RotationMatrix(result)
    }

    /// Creates a rotation that pivots around an axis.
    ///
    /// - Parameters:
    ///   - axis: The axis to rotate around (0=x, 1=y, 2=z).
    ///   - angle: The rotation angle in degrees.
    /// - Returns: The rotation matrix.
    public static func pivot(axis: Int, angle: Double) throws -> RotationMatrix {
        let result = Astronomy_Pivot(RotationMatrix.identity.raw, Int32(axis), angle)
        return try RotationMatrix(result)
    }
}

// MARK: - Coordinate System Conversions

extension RotationMatrix {
    // MARK: Equatorial J2000 (EQJ) conversions

    /// Creates a rotation from J2000 equatorial to ecliptic coordinates.
    public static func equatorialJ2000ToEcliptic() throws -> RotationMatrix {
        let result = Astronomy_Rotation_EQJ_ECL()
        return try RotationMatrix(result)
    }

    /// Creates a rotation from ecliptic to J2000 equatorial coordinates.
    public static func eclipticToEquatorialJ2000() throws -> RotationMatrix {
        let result = Astronomy_Rotation_ECL_EQJ()
        return try RotationMatrix(result)
    }

    /// Creates a rotation from J2000 equatorial to equatorial-of-date coordinates.
    ///
    /// - Parameter time: The time for the of-date frame.
    public static func equatorialJ2000ToEquatorialOfDate(at time: AstroTime) throws
        -> RotationMatrix
    {
        var t = time.raw
        let result = Astronomy_Rotation_EQJ_EQD(&t)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from equatorial-of-date to J2000 equatorial coordinates.
    ///
    /// - Parameter time: The time for the of-date frame.
    public static func equatorialOfDateToEquatorialJ2000(at time: AstroTime) throws
        -> RotationMatrix
    {
        var t = time.raw
        let result = Astronomy_Rotation_EQD_EQJ(&t)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from J2000 equatorial to horizontal coordinates.
    ///
    /// - Parameters:
    ///   - time: The observation time.
    ///   - observer: The geographic observer location.
    public static func equatorialJ2000ToHorizon(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        var t = time.raw
        let result = Astronomy_Rotation_EQJ_HOR(&t, observer.raw)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from horizontal to J2000 equatorial coordinates.
    ///
    /// - Parameters:
    ///   - time: The observation time.
    ///   - observer: The geographic observer location.
    public static func horizonToEquatorialJ2000(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        var t = time.raw
        let result = Astronomy_Rotation_HOR_EQJ(&t, observer.raw)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from J2000 equatorial to galactic coordinates.
    public static func equatorialJ2000ToGalactic() throws -> RotationMatrix {
        let result = Astronomy_Rotation_EQJ_GAL()
        return try RotationMatrix(result)
    }

    /// Creates a rotation from galactic to J2000 equatorial coordinates.
    public static func galacticToEquatorialJ2000() throws -> RotationMatrix {
        let result = Astronomy_Rotation_GAL_EQJ()
        return try RotationMatrix(result)
    }

    // MARK: Ecliptic (ECL) conversions

    /// Creates a rotation from ecliptic to horizontal coordinates.
    public static func eclipticToHorizon(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        var t = time.raw
        let result = Astronomy_Rotation_ECL_HOR(&t, observer.raw)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from horizontal to ecliptic coordinates.
    public static func horizonToEcliptic(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        var t = time.raw
        let result = Astronomy_Rotation_HOR_ECL(&t, observer.raw)
        return try RotationMatrix(result)
    }

    // MARK: Equatorial of Date (EQD) conversions

    /// Creates a rotation from equatorial-of-date to horizontal coordinates.
    public static func equatorialOfDateToHorizon(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        var t = time.raw
        let result = Astronomy_Rotation_EQD_HOR(&t, observer.raw)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from horizontal to equatorial-of-date coordinates.
    public static func horizonToEquatorialOfDate(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        var t = time.raw
        let result = Astronomy_Rotation_HOR_EQD(&t, observer.raw)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from equatorial-of-date to ecliptic coordinates.
    public static func equatorialOfDateToEcliptic(at time: AstroTime) throws -> RotationMatrix {
        var t = time.raw
        let result = Astronomy_Rotation_EQD_ECL(&t)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from ecliptic to equatorial-of-date coordinates.
    public static func eclipticToEquatorialOfDate(at time: AstroTime) throws -> RotationMatrix {
        var t = time.raw
        let result = Astronomy_Rotation_ECL_EQD(&t)
        return try RotationMatrix(result)
    }
}

// MARK: - Vector Rotation

extension Vector3D {
    /// Applies a rotation matrix to this vector.
    ///
    /// - Parameter rotation: The rotation matrix to apply.
    /// - Returns: The rotated vector.
    public func rotated(by rotation: RotationMatrix) throws -> Vector3D {
        let raw = astro_vector_t(
            status: ASTRO_SUCCESS,
            x: x,
            y: y,
            z: z,
            t: time.raw
        )
        let result = Astronomy_RotateVector(rotation.raw, raw)
        return try Vector3D(result)
    }
}

extension RotationMatrix: CustomStringConvertible {
    public var description: String {
        """
        [\(matrix[0]), \(matrix[1]), \(matrix[2])]
        [\(matrix[3]), \(matrix[4]), \(matrix[5])]
        [\(matrix[6]), \(matrix[7]), \(matrix[8])]
        """
    }
}
