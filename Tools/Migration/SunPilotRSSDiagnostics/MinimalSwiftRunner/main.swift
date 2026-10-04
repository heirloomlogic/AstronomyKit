@main
struct MinimalSwiftRunner {
    static func main() {
        if CommandLine.arguments.contains("--mapping-control") {
            _ = readLine()
        }
        print(0.0)
    }
}
