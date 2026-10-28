// expected-error: main actor-isolated property 'count'
@MainActor final class Model {
    var count = 1

    func invalid() {
        _ = KeyProjection(operation: Operation.self) { (_: Int) in self.count }
    }
}
