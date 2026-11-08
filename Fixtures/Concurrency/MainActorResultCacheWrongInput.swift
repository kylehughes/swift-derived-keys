import DerivedKeysUI

@MainActor
func invalidMainActorResultCacheInput() {
    let cache = MainActorResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { $0 }
    // expected-error: cannot convert value of type 'String' to expected argument type 'Int'
    _ = cache.value(for: "wrong")
}
