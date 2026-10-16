import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Whether this test process can run an exit test's child process.
///
/// A test that changes the process default Delta T model does so only inside
/// `#expect(processExitsWith:)`, so suites running in parallel in the test
/// process never see a temporary model. Swift Testing has no exit tests on
/// iOS, tvOS or watchOS, so those tests are compiled only for macOS and Linux.
///
/// On macOS, `swift test --sanitize=thread` or `--sanitize=address` loads the
/// sanitizer runtime late, and an exit test's child aborts before running its
/// body, so the tests are disabled there. Linux links the sanitizer runtime
/// into the test executable and the child runs instrumented.
enum ChildProcessIsolation {
    static let isSupported: Bool = {
        #if canImport(Darwin)
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        return dlsym(defaultHandle, "__tsan_init") == nil && dlsym(defaultHandle, "__asan_init") == nil
        #else
        return true
        #endif
    }()
}

#if os(macOS) || os(Linux)
/// Swift Testing discards an exit test's standard error unless the parent
/// observes it, and a failed exit test returns nothing to observe, so a
/// sanitizer report or `fatalError` message from the child would be lost.
/// The child sends its standard error to a file named by a tag and the parent's
/// process ID, and the parent records that file's text when the test fails.
extension ChildProcessIsolation {
    static func standardErrorPath(of tag: String, parent: pid_t) -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("AstronomyKit-\(parent)-\(tag).stderr").path
    }

    /// Call first in an exit test's body.
    static func keepStandardError(of tag: String) {
        let file = open(standardErrorPath(of: tag, parent: getppid()), O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard file >= 0 else { return }
        dup2(file, STDERR_FILENO)
        close(file)
    }

    /// The text the child for `tag` wrote to standard error; removes its file.
    static func takeStandardError(of tag: String) -> String? {
        let path = standardErrorPath(of: tag, parent: getpid())
        defer { try? FileManager.default.removeItem(atPath: path) }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// Records the child's standard error as an issue when `result` shows the
    /// exit test failed, and removes the file either way.
    static func reportStandardError(
        of tag: String, result: ExitTest.Result?, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let text = takeStandardError(of: tag), result == nil, !text.isEmpty else { return }
        Issue.record("Child process standard error:\n\(text)", sourceLocation: sourceLocation)
    }
}
#endif

extension Trait where Self == ConditionTrait {
    /// Disables a test whose exit test cannot run in this process; see
    /// `ChildProcessIsolation`.
    static var childProcessIsolation: Self {
        .enabled(
            if: ChildProcessIsolation.isSupported,
            "Exit-test child processes abort under a macOS sanitizer runtime")
    }
}
