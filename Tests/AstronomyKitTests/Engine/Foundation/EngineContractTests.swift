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
    enum NativeEngineViolationKind: Equatable {
        case cImport
        case mutex
    }

    struct NativeEngineViolation {
        let line: Int
        let kind: NativeEngineViolationKind
    }

    struct EntryPointReference {
        let name: String
        let file: String
        let line: Int

        var location: String { "\(file):\(line)" }
    }

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

    /// The lines of `source` that are not comments, numbered from 1.
    static func codeLines(in source: String) -> [(number: Int, text: Substring)] {
        source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .map { (number: $0.offset + 1, text: $0.element) }
            .filter { line in !line.text.drop { $0 == " " }.hasPrefix("//") }
    }

    static func nativeEngineViolations(in source: String) -> [NativeEngineViolation] {
        // Simple word boundaries, so `CLibAstronomy.x` and `Synchronization.Mutex`
        // still match; Unicode boundaries do not break at a period between letters.
        let cImport = #/\bimport\b.*\bCLibAstronomy\b/#.wordBoundaryKind(.simple)
        let mutex = #/\bMutex\b/#.wordBoundaryKind(.simple)
        var violations: [NativeEngineViolation] = []
        for line in codeLines(in: source) {
            if line.text.contains("CLibAstronomy"), line.text.firstMatch(of: cImport) != nil {
                violations.append(NativeEngineViolation(line: line.number, kind: .cImport))
            }
            if line.text.contains("Mutex"), line.text.firstMatch(of: mutex) != nil {
                violations.append(NativeEngineViolation(line: line.number, kind: .mutex))
            }
        }
        return violations
    }

    static func nativeEngineViolations(in file: URL) throws -> [NativeEngineViolation] {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let hasCImport = data.range(of: Data("CLibAstronomy".utf8)) != nil
        let hasMutex = data.range(of: Data("Mutex".utf8)) != nil
        guard hasCImport || hasMutex else { return [] }
        return nativeEngineViolations(in: try String(contentsOf: file, encoding: .utf8))
    }

    static func entryPointReferences(in source: String, file: String) -> [EntryPointReference] {
        guard source.contains("Astronomy_") else { return [] }
        var references: [EntryPointReference] = []
        for (offset, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        where line.contains("Astronomy_") {
            references.append(
                contentsOf: line.matches(of: #/\bAstronomy_\w+/#).map {
                    EntryPointReference(name: String($0.0), file: file, line: offset + 1)
                })
        }
        return references
    }

    static func entryPointReferences(in file: URL) throws -> [EntryPointReference] {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard data.range(of: Data("Astronomy_".utf8)) != nil else { return [] }
        let source = try String(contentsOf: file, encoding: .utf8)
        return entryPointReferences(in: source, file: file.lastPathComponent)
    }

    static func ownershipDiagnostic(
        for name: String, owners: [String], references: [EntryPointReference]
    ) -> String {
        let locations = references.filter { $0.name == name }.map(\.location).sorted().joined(separator: ", ")
        return "\(name) at \(locations): \(owners)"
    }

    @Test("Engine sources neither import the C engine nor use Mutex")
    func engineIsNative() throws {
        let files = try Self.swiftFiles(under: Self.sources.appendingPathComponent("Engine"))
        #expect(!files.isEmpty)
        for file in files {
            for violation in try Self.nativeEngineViolations(in: file) {
                let location = "\(file.lastPathComponent):\(violation.line)"
                #expect(violation.kind != .cImport, "\(location)")
                // Linux ThreadSanitizer does not model Mutex; see NATIVE_ENGINE.md.
                #expect(violation.kind != .mutex, "\(location)")
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
        var references: [EntryPointReference] = []
        for file in try Self.swiftFiles(under: Self.sources) {
            references.append(contentsOf: try Self.entryPointReferences(in: file))
        }
        #expect(!references.isEmpty)
        for name in Set(references.map(\.name)).sorted() {
            let listedOwners = owners[name] ?? []
            let diagnostic = Self.ownershipDiagnostic(for: name, owners: listedOwners, references: references)
            #expect(listedOwners.count == 1, "\(diagnostic)")
        }
    }

    @Test("Literal prefilters retain every contract guard")
    func literalPrefiltersRetainContractGuards() throws {
        let source = """
            // import CLibAstronomy; let lock = Mutex<Int>(0); Astronomy_Commented()
            import CLibAstronomy
            let lock = Mutex<Int>(0)
            let table = "QUJDREVGRw=="
            Astronomy_Unlisted()
            """

        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineContractTests-\(UUID().uuidString).swift")
        try source.write(to: fixture, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let violations = try Self.nativeEngineViolations(in: fixture)
        #expect(violations.map(\.line) == [2, 3])
        #expect(violations.map(\.kind) == [.cImport, .mutex])
        let references = try Self.entryPointReferences(in: fixture)
        #expect(references.map(\.name) == ["Astronomy_Commented", "Astronomy_Unlisted"])
        #expect(references.map(\.line) == [1, 5])
        let diagnostic = Self.ownershipDiagnostic(
            for: "Astronomy_Unlisted", owners: [], references: references)
        #expect(diagnostic == "Astronomy_Unlisted at \(fixture.lastPathComponent):5: []")
    }
}
