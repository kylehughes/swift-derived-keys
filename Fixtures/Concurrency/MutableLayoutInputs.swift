import DerivedKeysUIKit

// expected-error: cannot assign to property: 'proposal' is a 'let' constant
func invalidLayoutMutation(_ input: inout LayoutInputs<Int>, proposal: FittingProposal) {
    input.proposal = proposal
}
