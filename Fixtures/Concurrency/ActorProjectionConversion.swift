// expected-error: loses global actor 'MainActor'
@MainActor final class Model {
    var count = 1

    func invalid() {
        let project: @MainActor (Int) -> Int = { _ in self.count }
        _ = KeyProjection(operation: Operation.self, project: project)
    }
}
