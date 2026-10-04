import AstronomyModelPrototype
import Foundation

@main
struct ModelLinkedRunner {
    static func main() throws {
        if CommandLine.arguments.contains("--mapping-control") {
            _ = readLine()
        }
        if CommandLine.arguments.contains("--exercise-model") {
            let earth = try SunPilot.earth(tt: PilotTime(ut: 9_000).tt)
            FileHandle.standardOutput.write(Data("\(earth.vector.x)\n".utf8))
            return
        }
        FileHandle.standardOutput.write(Data("0.0\n".utf8))
    }
}
