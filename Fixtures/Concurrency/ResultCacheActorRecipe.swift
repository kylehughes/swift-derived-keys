// expected-error: main actor-isolated property 'count'
@MainActor final class ResultCacheModel {
    var count = 1
}

nonisolated func invalid(model: ResultCacheModel) {
    _ = ResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { _ in model.count }
}
