import DerivedKeysUIKit

@MainActor
func validLayoutAccess() throws {
    let cache = LayoutCache<Operation, LocalValue, LocalValue, LocalValue>(capacity: 2)
    let proposal = try FittingProposal(width: FittingDimension(points: 120))
    let owner = LocalOwner()
    _ = cache.value(for: LocalValue(1), proposal: proposal, context: LocalValue(2)) { input, _, context in
        LocalValue(input.value + context.value + owner.value)
    }
    requireSendable(LayoutInputs(input: 1, proposal: proposal))
}
