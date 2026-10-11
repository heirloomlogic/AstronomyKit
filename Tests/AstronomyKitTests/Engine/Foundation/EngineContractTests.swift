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
        case cEntryPoint
        case mutex
    }

    struct NativeEngineViolation: Equatable {
        let line: Int
        let kind: NativeEngineViolationKind
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

    /// Code lines that import the C engine, name one of its `Astronomy_`
    /// entry points, or use `Mutex`. Comments may still name C entry points
    /// where a function records which one it replaced.
    static func nativeEngineViolations(in source: String) -> [NativeEngineViolation] {
        // Simple word boundaries, so `CLibAstronomy.x` and `Synchronization.Mutex`
        // still match; Unicode boundaries do not break at a period between letters.
        let cImport = #/\bimport\b.*\bCLibAstronomy\b/#.wordBoundaryKind(.simple)
        let cEntryPoint = #/\bAstronomy_\w+/#.wordBoundaryKind(.simple)
        let mutex = #/\bMutex\b/#.wordBoundaryKind(.simple)
        var violations: [NativeEngineViolation] = []
        for line in codeLines(in: source) {
            if line.text.contains("CLibAstronomy"), line.text.firstMatch(of: cImport) != nil {
                violations.append(NativeEngineViolation(line: line.number, kind: .cImport))
            }
            if line.text.contains("Astronomy_"), line.text.firstMatch(of: cEntryPoint) != nil {
                violations.append(NativeEngineViolation(line: line.number, kind: .cEntryPoint))
            }
            if line.text.contains("Mutex"), line.text.firstMatch(of: mutex) != nil {
                violations.append(NativeEngineViolation(line: line.number, kind: .mutex))
            }
        }
        return violations
    }

    static func nativeEngineViolations(in file: URL) throws -> [NativeEngineViolation] {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let prefilters = ["CLibAstronomy", "Astronomy_", "Mutex"].map { Data($0.utf8) }
        guard prefilters.contains(where: { data.range(of: $0) != nil }) else { return [] }
        return nativeEngineViolations(in: try String(contentsOf: file, encoding: .utf8))
    }

    @Test("No shipping source imports the C engine or calls a C entry point")
    func shippingSourcesAreNative() throws {
        let files = try Self.swiftFiles(under: Self.sources)
        #expect(files.count > 50)
        for file in files {
            for violation in try Self.nativeEngineViolations(in: file) where violation.kind != .mutex {
                #expect(violation.kind == .mutex, "\(file.lastPathComponent):\(violation.line) \(violation.kind)")
            }
        }
    }

    @Test("Engine sources do not use Mutex")
    func engineUsesNoMutex() throws {
        let files = try Self.swiftFiles(under: Self.sources.appendingPathComponent("Engine"))
        #expect(!files.isEmpty)
        for file in files {
            for violation in try Self.nativeEngineViolations(in: file) where violation.kind == .mutex {
                // Linux ThreadSanitizer does not model Mutex; see NATIVE_ENGINE.md.
                #expect(violation.kind != .mutex, "\(file.lastPathComponent):\(violation.line)")
            }
        }
    }

    @Test("The shipping target declares no dependency on the C target")
    func shippingTargetHasNoCDependency() throws {
        let manifest = try String(contentsOf: Self.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let target = try #require(manifest.firstRange(of: ".target(\n            name: \"AstronomyKit\""))
        let declaration = manifest[target.lowerBound...].prefix { $0 != ")" }
        #expect(!declaration.contains("dependencies"), "\(declaration)")
        #expect(!declaration.contains("CLibAstronomy"), "\(declaration)")
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
        #expect(
            violations == [
                NativeEngineViolation(line: 2, kind: .cImport),
                NativeEngineViolation(line: 3, kind: .mutex),
                NativeEngineViolation(line: 5, kind: .cEntryPoint),
            ])
    }
}
