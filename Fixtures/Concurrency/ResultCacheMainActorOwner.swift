@MainActor final class OwnedModel {
    var count = 1
    var scale = 2

    // Main-actor key paths and closures stay in the owner's region because the
    // cache, source, and projection are not Sendable.
    private var cache: ResultCache<OwnedModel, Int>
    private let source: KeySource<OwnedModel>
    private let projection: KeyProjection<Operation, OwnedModel, Int>

    init() {
        cache = ResultCache<OwnedModel, Int>(dependingOn: \.count, \.scale, capacity: 2) { model in
            model.count * model.scale
        }
        source = KeySource<OwnedModel>("count", provider: { $0.count })
        projection = KeyProjection(operation: Operation.self) { (model: OwnedModel) in model.count }
    }

    func value() -> Int {
        let total = cache.value(for: self)
        _ = source.snapshot(for: self)
        _ = projection.key(for: self, context: "en")
        return total
    }

    func reading(from other: OwnedModel) -> Int {
        var local = ResultCache<OwnedModel, Int>(dependingOn: \.count, capacity: 1) { _ in self.count }
        return local.value(for: other)
    }
}
