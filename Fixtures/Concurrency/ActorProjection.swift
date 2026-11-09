// expected-error: main actor-isolated property 'count'
@MainActor final class Model {
    var count = 1
}

nonisolated func invalid(model: Model) {
    _ = KeyProjection(operation: Operation.self) { (_: Int) in model.count }
}
