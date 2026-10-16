import Foundation
import Testing

#if os(macOS) || os(Linux)
@Suite("Exit-test child standard error", .childProcessIsolation)
struct ChildProcessIsolationTests {
    @Test("A failed exit test's standard error reaches the parent")
    func failedChildStandardErrorIsKept() async {
        await withKnownIssue("The child exits with status 3") {
            await #expect(processExitsWith: .success) {
                ChildProcessIsolation.keepStandardError(of: "ChildProcessIsolationTests.failed")
                FileHandle.standardError.write(Data("child standard error marker\n".utf8))
                exit(3)
            }
        }
        let text = ChildProcessIsolation.takeStandardError(of: "ChildProcessIsolationTests.failed")
        #expect(text?.contains("child standard error marker") == true)
    }
}
#endif
