import DerivedKeysUI

@MainActor
func invalidBindingInitializer() {
    // expected-error: initializer is inaccessible due to 'fileprivate' protection level
    _ = SizeCacheBinding<Int>(depth: 1, capture: { _ in fatalError("Must not compile") }, lookup: { _, size in size })
}
