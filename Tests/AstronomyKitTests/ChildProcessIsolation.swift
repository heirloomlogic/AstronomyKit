import Testing

#if canImport(Darwin)
    import Darwin
#endif

/// Whether this test process can run an exit test's child process.
///
/// A test that changes the process default Delta T model does so only inside
/// `#expect(processExitsWith:)`, so suites running in parallel in the test
/// process never see a temporary model. Swift Testing has no exit tests on
/// iOS, tvOS or watchOS, so those tests are compiled only for macOS, Linux and
/// Windows.
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

extension Trait where Self == ConditionTrait {
    /// Disables a test whose exit test cannot run in this process; see
    /// `ChildProcessIsolation`.
    static var childProcessIsolation: Self {
        .enabled(
            if: ChildProcessIsolation.isSupported,
            "Exit-test child processes abort under a macOS sanitizer runtime")
    }
}
