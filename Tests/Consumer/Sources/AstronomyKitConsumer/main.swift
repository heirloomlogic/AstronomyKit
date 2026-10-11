import AstronomyKit

let time = AstroTime(year: 2026, month: 1, day: 2)
let position = try CelestialBody.sun.geocentricPosition(at: time)
precondition(position.x.isFinite && position.y.isFinite && position.z.isFinite)
