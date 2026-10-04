import AstronomyModelPrototype

@main
struct ModelLinkedRunner {
    static func main() throws {
        if CommandLine.arguments.contains("--mapping-control") {
            _ = readLine()
        }
        if CommandLine.arguments.contains("--exercise-model") {
            let earth = try SunPilot.earth(tt: PilotTime(ut: 9_000).tt)
            print(earth.vector.x)
            return
        }
        print(0.0)
    }
}
