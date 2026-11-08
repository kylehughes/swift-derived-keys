import DerivedKeysUI

private final class ResultFixtureInput {
    var title = "Text"
    let child = ResultFixtureChild()
}

private final class ResultFixtureChild {
    var revision = 1
}

@MainActor
private func validMainActorResultCacheAccess() {
    typealias Request = (root: ResultFixtureInput, width: Int)
    let owner = LocalOwner()
    let cache = MainActorResultCache<Request, LocalOwner>(
        dependingOn: \.root.title,
        \.root.child.revision,
        \.width,
        capacity: 2
    ) { request in
        owner.value = request.width
        return owner
    }
    let empty = MainActorResultCache<ResultFixtureInput, Int>(capacity: 0) { _ in 1 }
    let whole = MainActorResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { $0 }
    let root = ResultFixtureInput()
    _ = cache.value(for: (root, 120))
    cache.removeValue(for: (root, 120))
    cache.removeAll()
    _ = cache.count
    _ = empty.value(for: root)
    _ = whole.capacity
}
