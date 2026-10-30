import DerivedKeysUI

// expected-error: call to main actor-isolated instance method 'size(of:toFit:)' in a synchronous nonisolated context
func invalidBindingAccess(_ binding: SizeCacheBinding<Int>) {
    _ = binding.size(of: 1, toFit: .zero)
}
