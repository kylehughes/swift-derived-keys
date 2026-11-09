import DerivedKeysUI

// expected-error: call to main actor-isolated instance method 'value(for:proposal:context:compute:)' in a synchronous nonisolated context
func invalidLayoutAccess(_ cache: LayoutCache<Operation, Int, Int, Int>, proposal: FittingProposal) {
    _ = cache.value(for: 1, proposal: proposal, context: 2) { input, _, _ in input }
}
