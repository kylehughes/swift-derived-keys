import DerivedKeysUI

@MainActor
func invalidMainActorResultCacheValue() {
    // expected-error: cannot convert value of type 'String' to closure result type 'Int'
    _ = MainActorResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { _ in "wrong" }
}
