// expected-error: risks causing data races
@MainActor final class DetachedModel {
    var count = 1

    func invalid() {
        var cache = ResultCache<DetachedModel, Int>(dependingOn: \.count, capacity: 1) { $0.count }
        Task.detached {
            _ = cache.value(for: self)
        }
        _ = cache.count
    }
}
