//
//  LunarNode.swift
//  AstronomyKit
//
//  Lunar node crossing calculations.
//

// MARK: - Node Kind

/// The type of lunar node crossing.
public enum NodeKind: Sendable, Equatable, Hashable, Codable {
    /// The Moon crosses from south to north of the ecliptic plane.
    case ascending

    /// The Moon crosses from north to south of the ecliptic plane.
    case descending

    init(_ kind: Engine.Events.LunarNodeKind) {
        self = kind == .ascending ? .ascending : .descending
    }

    var engine: Engine.Events.LunarNodeKind { self == .ascending ? .ascending : .descending }

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
    /// A textual representation of the node type.
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

    /// Creates a lunar node from the engine's.
    init(_ node: Engine.Events.LunarNode) {
        self.kind = NodeKind(node.kind)
        self.time = AstroTime(node.time)
    }
}

extension LunarNode: CustomStringConvertible {
    /// A textual representation showing the node symbol, type, and time.
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
    /// - Throws: `AstronomyError.badTime` if the search would evaluate the Moon outside
    ///   the accepted time range (see ``AstroTime``), which includes a non-finite
    ///   `startTime`, or another `AstronomyError` if the search fails.
    public static func searchNode(after startTime: AstroTime) throws -> LunarNode {
        LunarNode(try Engine.Events.searchLunarNode(after: startTime.engine))
    }

    /// Finds the next lunar node crossing after a given node.
    ///
    /// - Parameter node: The previous node crossing.
    /// - Returns: The next node crossing.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nextNode(after node: LunarNode) throws -> LunarNode {
        LunarNode(try Engine.Events.nextLunarNode(after: node.kind.engine, at: node.time.engine))
    }

    /// Returns all lunar node crossings within a date range.
    ///
    /// - Parameters:
    ///   - startTime: The start of the range.
    ///   - endTime: The end of the range.
    /// - Returns: An array of node crossings.
    /// - Throws: `AstronomyError` if the search fails.
    public static func nodeCrossings(
        from startTime: AstroTime,
        to endTime: AstroTime
    ) throws -> [LunarNode] {
        var nodes: [LunarNode] = []
        var current = try searchNode(after: startTime)

        while current.time < endTime {
            nodes.append(current)
            current = try nextNode(after: current)
        }

        return nodes
    }
}
