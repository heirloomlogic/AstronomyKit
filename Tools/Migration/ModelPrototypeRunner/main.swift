import AstronomyModelPrototype

func nanoseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    return components.seconds * 1_000_000_000 + Int64(components.attoseconds / 1_000_000_000)
}

let mode = CommandLine.arguments.dropFirst().first ?? "first"
switch mode {
case "first":
    let start = ContinuousClock.now
    guard let value = PrototypeModelData.polynomialBitPattern(body: .earth, index: 0) else {
        preconditionFailure("Generated Earth polynomial table is empty")
    }
    let elapsed = start.duration(to: .now)
    print("{\"mode\":\"first\",\"elapsedNanoseconds\":\(nanoseconds(elapsed)),\"value\":\(value)}")
case "sweep":
    let start = ContinuousClock.now
    let checksum = PrototypeModelData.wholeModelFNV64()
    let elapsed = start.duration(to: .now)
    print(
        "{\"mode\":\"sweep\",\"elapsedNanoseconds\":\(nanoseconds(elapsed)),\"checksum\":\(checksum)}")
default:
    fatalError("Expected first or sweep")
}
