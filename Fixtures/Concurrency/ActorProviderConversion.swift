// expected-error: loses global actor 'MainActor'
@MainActor final class Model {
    var count = 1

    func invalid() {
        let provider: @MainActor (Int) -> Int = { _ in self.count }
        _ = KeySource<Int>("count", provider: provider)
    }
}
