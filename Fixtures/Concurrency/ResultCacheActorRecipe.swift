// expected-error: main actor-isolated property 'count'
@MainActor final class ResultCacheModel {
    var count = 1

    func invalid() {
        _ = ResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { _ in self.count }
    }
}
