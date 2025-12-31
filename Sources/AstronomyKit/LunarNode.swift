//
//  LunarNode.swift
//  AstronomyKit
//
//  Lunar node crossing calculations.
//

import CLibAstronomy

// MARK: - Node Kind

/// The type of lunar node crossing.
public enum NodeKind: Sendable, Equatable, Hashable, Codable {
    /// The Moon crosses from south to north of the ecliptic plane.
    case ascending

    /// The Moon crosses from north to south of the ecliptic plane.
    case descending

    internal init(_ raw: astro_node_kind_t) {
        switch raw {
        case ASCENDING_NODE:
            self = .ascending
        default:
            self = .descending
        }
    }

    /// A human-readable name.
    public var name: String {
        switch self {
        case .ascending: return "Ascending Node"
        case .descending: return "Descending Node"
        }
    }

    /// Traditional astrological symbol name.
    public var symbol: String {
        switch self {
        case .ascending: return "☊"  // North Node / Rahu
        case .descending: return "☋"  // South Node / Ketu
        }
    }
}

extension NodeKind: CustomStringConvertible {
    public var description: String { name }
}

// MARK: - Lunar Node

/// Information about the Moon crossing the ecliptic plane.
///
/// Lunar nodes are the two points where the Moon's orbit crosses
/// the ecliptic plane. The ascending node is where the Moon crosses
/// from south to north, and the descending node is where it crosses
/// from north to south.
///
/// ## Example
///
/// ```swift
/// let node = try Moon.searchNode(after: .now)
/// print("\(node.kind.symbol) \(node.kind.name) at \(node.time)")
/// ```
public struct LunarNode: Sendable, Equatable {
    /// The type of node crossing.
    public let kind: NodeKind

    /// The time when the Moon crosses the ecliptic plane.
    public let time: AstroTime

    /// Creates a lunar node from the C structure.
    internal init(_ raw: astro_node_event_t) throws {
        if let error = AstronomyError(status: raw.status) {
            throw error
        }
        self.kind = NodeKind(raw.kind)
        self.time = AstroTime(raw: raw.time)
    }
}

extension LunarNode: CustomStringConvertible {
    public var description: String {
        "\(kind.symbol) \(kind.name) at \(time)"
    }
}

// MARK: - Moon Node Functions

extension Moon {
    /// Searches for the next lunar node crossing.
    ///
    /// - Parameter startTime: The time to start searching from.
    /// - Returns: The next node crossing.
    /// - Throws: `AstronomyError` if the search fails.
    public static func searchNode(after startTime: AstroTime) throws -> LunarNode {
        let result = Astronomy_SearchMoonNode(startTime.raw)
        return try LunarNode(result)
    }

    /// Finds the next lunar node crossing after a given node.
    ///
    /// - Parameter node: The previous node crossing.
    /// - Returns: The next node crossing.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextNode(after node: LunarNode) throws -> LunarNode {
        let raw = astro_node_event_t(
            status: ASTRO_SUCCESS,
            time: node.time.raw,
            kind: node.kind == .ascending ? ASCENDING_NODE : DESCENDING_NODE
        )
        let result = Astronomy_NextMoonNode(raw)
        return try LunarNode(result)
    }

    /// Returns all lunar node crossings within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of node crossings.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nodeCrossings(from startTime: AstroTime, to endTime: AstroTime) throws
        -> [LunarNode] {
        var nodes: [LunarNode] = []
        var current = try searchNode(after: startTime)

        while current.time < endTime {
            nodes.append(current)
            current = try nextNode(after: current)
        }

        return nodes
    }
}
