//
//  EngineContractTests.swift
//  AstronomyKit
//
//  Checks NATIVE_ENGINE.md against the source tree.
//

import Foundation
import Testing

@Suite("Native engine contract")
struct EngineContractTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Foundation
        .deletingLastPathComponent()  // Engine
        .deletingLastPathComponent()  // AstronomyKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()

    static let sources = root.appendingPathComponent("Sources/AstronomyKit")

    /// The Swift files under `directory`, recursively.
    static func swiftFiles(under directory: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("Engine sources neither import the C engine nor use Mutex")
    func engineIsNative() throws {
        let files = try Self.swiftFiles(under: Self.sources.appendingPathComponent("Engine"))
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("import CLibAstronomy"), "\(file.lastPathComponent)")
            // Linux ThreadSanitizer does not model Mutex; see NATIVE_ENGINE.md.
            #expect(!text.contains("Mutex<"), "\(file.lastPathComponent)")
        }
    }

    @Test("Every C entry point the Swift layer names has exactly one owner in the contract")
    func everyEntryPointHasOneOwner() throws {
        let contract = try String(contentsOf: Self.root.appendingPathComponent("NATIVE_ENGINE.md"), encoding: .utf8)
        // Owner lines look like "- #86: `Astronomy_Pivot`, ...".
        var owners: [String: [String]] = [:]
        for line in contract.split(separator: "\n") {
            guard line.hasPrefix("- #"), let owner = line.dropFirst(2).split(separator: ":").first else { continue }
            for name in line.matches(of: /`(Astronomy_\w+)`/) {
                owners[String(name.1), default: []].append(String(owner))
            }
        }
        var named = Set<String>()
        for file in try Self.swiftFiles(under: Self.sources) {
            let text = try String(contentsOf: file, encoding: .utf8)
            named.formUnion(text.matches(of: /\bAstronomy_\w+/).map { String($0.0) })
        }
        #expect(!named.isEmpty)
        for name in named.sorted() {
            #expect(owners[name]?.count == 1, "\(name): \(owners[name] ?? [])")
        }
    }
}
