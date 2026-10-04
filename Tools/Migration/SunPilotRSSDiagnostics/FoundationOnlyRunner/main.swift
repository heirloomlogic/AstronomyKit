import Foundation

@main
struct FoundationOnlyRunner {
    static func main() {
        if CommandLine.arguments.contains("--mapping-control") {
            _ = readLine()
        }
        FileHandle.standardOutput.write(Data("0.0\n".utf8))
    }
}
