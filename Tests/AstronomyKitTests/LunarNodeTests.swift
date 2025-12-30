//
//  LunarNodeTests.swift
//  AstronomyKit
//
//  Tests for Lunar Node functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Lunar Node")
struct LunarNodeTests {

    @Test("Search lunar node finds ascending or descending")
    func searchLunarNode() throws {
        let startTime = AstroTime(year: 2025, month: 1, day: 1)
        let node = try Moon.searchNode(after: startTime)

        #expect(node.time > startTime)
        #expect(node.kind == .ascending || node.kind == .descending)
    }

    @Test("Next node alternates")
    func nextNodeAlternates() throws {
        let startTime = AstroTime(year: 2025, month: 1, day: 1)
        let first = try Moon.searchNode(after: startTime)
        let second = try Moon.nextNode(after: first)

        #expect(second.time > first.time)
        #expect(second.kind != first.kind)  // Alternates between ascending and descending
    }

    @Test("Node kind has correct names")
    func nodeKindNames() {
        #expect(NodeKind.ascending.name == "Ascending Node")
        #expect(NodeKind.descending.name == "Descending Node")
    }

    @Test("Node kind has correct symbols")
    func nodeKindSymbols() {
        #expect(NodeKind.ascending.symbol == "☊")
        #expect(NodeKind.descending.symbol == "☋")
    }

    @Test("Node crossings in range")
    func nodeCrossingsInRange() throws {
        let start = AstroTime(year: 2025, month: 1, day: 1)
        let end = AstroTime(year: 2025, month: 3, day: 1)

        let nodes = try Moon.nodeCrossings(from: start, to: end)

        // ~2 months should have ~4 node crossings (ascending and descending each ~2 weeks apart)
        #expect(nodes.count >= 3)
        #expect(nodes.count <= 5)
    }
}
