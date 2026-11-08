import DerivedKeysUI

// expected-error: call to main actor-isolated instance method 'value(for:)' in a synchronous nonisolated context
func invalidMainActorResultCacheAccess(_ cache: MainActorResultCache<Int, Int>) {
    _ = cache.value(for: 1)
}
