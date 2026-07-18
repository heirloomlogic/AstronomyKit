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
public struct RotationMatrix: Sendable {
    /// The 3x3 rotation matrix, stored inline as the C structure to avoid a heap
    /// allocation per matrix.
    private let storage: astro_rotation_t

    /// Access matrix element at row, column.
    ///
    /// Traps on an out-of-range index, matching the previous array-backed behavior.
    public subscript(row: Int, col: Int) -> Double {
        switch (row, col) {
        case (0, 0): return storage.rot.0.0
        case (0, 1): return storage.rot.0.1
        case (0, 2): return storage.rot.0.2
        case (1, 0): return storage.rot.1.0
        case (1, 1): return storage.rot.1.1
        case (1, 2): return storage.rot.1.2
        case (2, 0): return storage.rot.2.0
        case (2, 1): return storage.rot.2.1
        case (2, 2): return storage.rot.2.2
        default: preconditionFailure("RotationMatrix index (\(row), \(col)) out of range")
        }
    }

    /// Creates a rotation matrix from the C structure.
    init(_ raw: astro_rotation_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        var normalized = raw
        normalized.status = ASTRO_SUCCESS
        self.storage = normalized
    }

    /// Creates a rotation matrix from a C structure known to be valid, skipping the
    /// status check. For internally constructed matrices only (e.g. ``identity``).
    private init(unchecked raw: astro_rotation_t) {
        self.storage = raw
    }

    /// The internal C representation.
    var raw: astro_rotation_t { storage }
}

// MARK: - Matrix Operations

extension RotationMatrix {
    /// The identity rotation matrix (no rotation).
    public static var identity: RotationMatrix {
        var rot = astro_rotation_t()
        rot.status = ASTRO_SUCCESS
        rot.rot.0 = (1, 0, 0)
        rot.rot.1 = (0, 1, 0)
        rot.rot.2 = (0, 0, 1)
        return RotationMatrix(unchecked: rot)
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
    /// - Throws: `AstronomyError` if the combination fails.
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
    /// - Throws: `AstronomyError` if the pivot fails.
    public static func pivot(axis: Int, angle: Double) throws -> RotationMatrix {
        guard (0...2).contains(axis) else {
            throw AstronomyError.invalidParameter
        }
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
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the rotation cannot be computed.
    public static func equatorialJ2000ToEquatorialOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_EQJ_EQD(&rawTime)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from equatorial-of-date to J2000 equatorial coordinates.
    ///
    /// - Parameter time: The time for the of-date frame.
    /// - Returns: The rotation matrix.
    /// - Throws: `AstronomyError` if the rotation cannot be computed.
    public static func equatorialOfDateToEquatorialJ2000(
        at time: AstroTime
    ) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_EQD_EQJ(&rawTime)
        return try RotationMatrix(result)
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
        var rawTime = time.raw
        let result = Astronomy_Rotation_EQJ_HOR(&rawTime, try observer.validatedRaw())
        return try RotationMatrix(result)
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
        var rawTime = time.raw
        let result = Astronomy_Rotation_HOR_EQJ(&rawTime, try observer.validatedRaw())
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
        var rawTime = time.raw
        let result = Astronomy_Rotation_ECL_HOR(&rawTime, try observer.validatedRaw())
        return try RotationMatrix(result)
    }

    /// Creates a rotation from horizontal to ecliptic coordinates.
    public static func horizonToEcliptic(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_HOR_ECL(&rawTime, try observer.validatedRaw())
        return try RotationMatrix(result)
    }

    // MARK: Equatorial of Date (EQD) conversions

    /// Creates a rotation from equatorial-of-date to horizontal coordinates.
    public static func equatorialOfDateToHorizon(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_EQD_HOR(&rawTime, try observer.validatedRaw())
        return try RotationMatrix(result)
    }

    /// Creates a rotation from horizontal to equatorial-of-date coordinates.
    public static func horizonToEquatorialOfDate(
        at time: AstroTime,
        from observer: Observer
    ) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_HOR_EQD(&rawTime, try observer.validatedRaw())
        return try RotationMatrix(result)
    }

    /// Creates a rotation from equatorial-of-date to ecliptic coordinates.
    public static func equatorialOfDateToEcliptic(at time: AstroTime) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_EQD_ECL(&rawTime)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from ecliptic to equatorial-of-date coordinates.
    public static func eclipticToEquatorialOfDate(at time: AstroTime) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_ECL_EQD(&rawTime)
        return try RotationMatrix(result)
    }

    // MARK: Ecliptic of Date (ECT) conversions

    /// Creates a rotation from J2000 equatorial to ecliptic-of-date coordinates.
    public static func equatorialJ2000ToEclipticOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_EQJ_ECT(&rawTime)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from ecliptic-of-date to J2000 equatorial coordinates.
    public static func eclipticOfDateToEquatorialJ2000(
        at time: AstroTime
    ) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_ECT_EQJ(&rawTime)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from equatorial-of-date to ecliptic-of-date coordinates.
    public static func equatorialOfDateToEclipticOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_EQD_ECT(&rawTime)
        return try RotationMatrix(result)
    }

    /// Creates a rotation from ecliptic-of-date to equatorial-of-date coordinates.
    public static func eclipticOfDateToEquatorialOfDate(
        at time: AstroTime
    ) throws -> RotationMatrix {
        var rawTime = time.raw
        let result = Astronomy_Rotation_ECT_EQD(&rawTime)
        return try RotationMatrix(result)
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

// MARK: - State Vector Rotation

extension StateVector {
    /// Applies a rotation matrix to both the position and velocity vectors.
    ///
    /// - Parameter rotation: The rotation matrix to apply.
    /// - Returns: The rotated state vector.
    /// - Throws: `AstronomyError` if the rotation fails.
    public func rotated(by rotation: RotationMatrix) throws -> StateVector {
        let raw = astro_state_vector_t(
            status: ASTRO_SUCCESS,
            x: position.x,
            y: position.y,
            z: position.z,
            vx: velocity.x,
            vy: velocity.y,
            vz: velocity.z,
            t: time.raw
        )
        let result = Astronomy_RotateState(rotation.raw, raw)
        return try StateVector(result)
    }
}

// MARK: - Equatable

extension RotationMatrix: Equatable {
    /// Two rotation matrices are equal when all nine elements match.
    ///
    /// Written by hand because the inline C-tuple storage has no synthesized conformance.
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
