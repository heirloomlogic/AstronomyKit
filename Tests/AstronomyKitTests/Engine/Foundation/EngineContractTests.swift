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

    /// The lines of `file` that are not comments, numbered from 1.
    static func codeLines(of file: URL) throws -> [(number: Int, text: Substring)] {
        let text = try String(contentsOf: file, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .map { (number: $0.offset + 1, text: $0.element) }
            .filter { line in !line.text.drop { $0 == " " }.hasPrefix("//") }
    }

    @Test("Engine sources neither import the C engine nor use Mutex")
    func engineIsNative() throws {
        // Simple word boundaries, so `CLibAstronomy.x` and `Synchronization.Mutex`
        // still match; Unicode boundaries do not break at a period between letters.
        let cImport = #/\bimport\b.*\bCLibAstronomy\b/#.wordBoundaryKind(.simple)
        let mutex = #/\bMutex\b/#.wordBoundaryKind(.simple)
        let files = try Self.swiftFiles(under: Self.sources.appendingPathComponent("Engine"))
        #expect(!files.isEmpty)
        for file in files {
            for line in try Self.codeLines(of: file) {
                let location = "\(file.lastPathComponent):\(line.number)"
                #expect(line.text.firstMatch(of: cImport) == nil, "\(location)")
                // Linux ThreadSanitizer does not model Mutex; see NATIVE_ENGINE.md.
                #expect(line.text.firstMatch(of: mutex) == nil, "\(location)")
            }
        }
    }

    /// The shared registry keeps every cache it holds for the life of the
    /// process, so a cache made anywhere but a `static let` could grow it
    /// without bound. Any code line outside `EngineCache.swift` that names
    /// `BoundedCache` must declare a `static let`, which covers a call, an
    /// `.init` call, an inferred type annotation and a type alias.
    @Test("Engine code names BoundedCache only in static let declarations")
    func cachesAreStatic() throws {
        let files = try Self.swiftFiles(under: Self.sources.appendingPathComponent("Engine"))
        let named = #/\bBoundedCache\b/#.wordBoundaryKind(.simple)
        for file in files where file.lastPathComponent != "EngineCache.swift" {
            for line in try Self.codeLines(of: file) where line.text.firstMatch(of: named) != nil {
                #expect(line.text.contains("static let"), "\(file.lastPathComponent):\(line.number)")
            }
        }
    }

    @Test("Every C entry point the Swift layer names has exactly one owner in the contract")
    func everyEntryPointHasOneOwner() throws {
        let contract = try String(contentsOf: Self.root.appendingPathComponent("NATIVE_ENGINE.md"), encoding: .utf8)
        // Owner lines look like "- #86: `Astronomy_Pivot`, ...".
        var owners: [String: [String]] = [:]
        for line in contract.split(separator: "\n") {
            guard line.hasPrefix("- #"), let owner = line.dropFirst(2).split(separator: ":").first else { continue }
            for name in line.matches(of: #/`(Astronomy_\w+)`/#) {
                owners[String(name.1), default: []].append(String(owner))
            }
        }
        var named = Set<String>()
        for file in try Self.swiftFiles(under: Self.sources) {
            let text = try String(contentsOf: file, encoding: .utf8)
            named.formUnion(text.matches(of: #/\bAstronomy_\w+/#).map { String($0.0) })
        }
        #expect(!named.isEmpty)
        for name in named.sorted() {
            #expect(owners[name]?.count == 1, "\(name): \(owners[name] ?? [])")
        }
    }
}
