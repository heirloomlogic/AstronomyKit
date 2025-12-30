//
//  AstronomyError.swift
//  AstronomyKit
//
//  Swift error types for astronomy calculations.
//

import CLibAstronomy

/// Errors that can occur during astronomy calculations.
public enum AstronomyError: Error, Equatable, Hashable, Sendable {
    /// A placeholder indicating data is not yet initialized.
    case notInitialized
    
    /// The celestial body was not valid for this operation.
    case invalidBody
    
    /// A numeric solver failed to converge.
    case noConvergence
    
    /// The provided date/time is outside the allowed range.
    case badTime
    
    /// Vector magnitude is too small to normalize.
    case badVector
    
    /// Search could not find an ascending root crossing in the time interval.
    case searchFailure
    
    /// Earth cannot be treated as a celestial body from Earth.
    case earthNotAllowed
    
    /// No lunar quarter occurs in the specified time range.
    case noMoonQuarter
    
    /// Internal error: wrong moon quarter found.
    case wrongMoonQuarter
    
    /// Internal error indicating a bug.
    case internalError
    
    /// A parameter value was invalid.
    case invalidParameter
    
    /// Special-case logic for Neptune/Pluto apsis failed.
    case failApsis
    
    /// A provided buffer is too small.
    case bufferTooSmall
    
    /// Memory allocation failed.
    case outOfMemory
    
    /// Initial state vectors did not have matching times.
    case inconsistentTimes
    
    /// An unknown error occurred.
    case unknown(Int32)
    
    /// Creates an error from a C status code.
    internal init?(status: astro_status_t) {
        switch status {
        case ASTRO_SUCCESS:
            return nil
        case ASTRO_NOT_INITIALIZED:
            self = .notInitialized
        case ASTRO_INVALID_BODY:
            self = .invalidBody
        case ASTRO_NO_CONVERGE:
            self = .noConvergence
        case ASTRO_BAD_TIME:
            self = .badTime
        case ASTRO_BAD_VECTOR:
            self = .badVector
        case ASTRO_SEARCH_FAILURE:
            self = .searchFailure
        case ASTRO_EARTH_NOT_ALLOWED:
            self = .earthNotAllowed
        case ASTRO_NO_MOON_QUARTER:
            self = .noMoonQuarter
        case ASTRO_WRONG_MOON_QUARTER:
            self = .wrongMoonQuarter
        case ASTRO_INTERNAL_ERROR:
            self = .internalError
        case ASTRO_INVALID_PARAMETER:
            self = .invalidParameter
        case ASTRO_FAIL_APSIS:
            self = .failApsis
        case ASTRO_BUFFER_TOO_SMALL:
            self = .bufferTooSmall
        case ASTRO_OUT_OF_MEMORY:
            self = .outOfMemory
        case ASTRO_INCONSISTENT_TIMES:
            self = .inconsistentTimes
        default:
            self = .unknown(Int32(bitPattern: status.rawValue))
        }
    }
}

extension AstronomyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notInitialized:
            return "Data not initialized"
        case .invalidBody:
            return "Invalid celestial body"
        case .noConvergence:
            return "Numeric solver failed to converge"
        case .badTime:
            return "Date/time outside allowed range"
        case .badVector:
            return "Vector magnitude too small to normalize"
        case .searchFailure:
            return "Search failed to find result in time interval"
        case .earthNotAllowed:
            return "Cannot observe Earth from Earth"
        case .noMoonQuarter:
            return "No lunar quarter in time range"
        case .wrongMoonQuarter:
            return "Internal error: wrong moon quarter"
        case .internalError:
            return "Internal calculation error"
        case .invalidParameter:
            return "Invalid parameter value"
        case .failApsis:
            return "Failed to calculate apsis"
        case .bufferTooSmall:
            return "Buffer too small"
        case .outOfMemory:
            return "Out of memory"
        case .inconsistentTimes:
            return "State vectors have inconsistent times"
        case .unknown(let code):
            return "Unknown error (code: \(code))"
        }
    }
}
