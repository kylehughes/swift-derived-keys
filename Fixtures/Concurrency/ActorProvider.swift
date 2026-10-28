// expected-error: main actor-isolated property 'count'
@MainActor final class Model {
    var count = 1

    func invalid() {
        _ = KeySource<Int>("count", provider: { _ in self.count })
    }
}
