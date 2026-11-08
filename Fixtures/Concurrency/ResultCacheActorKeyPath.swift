// expected-error: type 'KeyPath<ResultCacheModel, Int>' does not conform to the 'Sendable' protocol
@MainActor final class ResultCacheModel {
    var count = 1

    func invalid() {
        _ = ResultCache<ResultCacheModel, Int>(dependingOn: \.count, capacity: 1) { _ in 1 }
    }
}
