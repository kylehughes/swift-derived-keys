import DerivedKeys

/// A layout input paired with the fitting proposal it was measured for.
///
/// Equality compares both `input` and `proposal`. The input must keep stable equality and
/// hashing while a key containing it is stored; see <doc:CacheContract>.
public struct LayoutInputs<Input>: Hashable where Input: Hashable {
    /// The layout-relevant values you captured.
    public let input: Input
    /// The proposal passed to the layout calculation.
    public let proposal: FittingProposal

    /// Pairs an input with the proposal used by a layout calculation.
    public init(input: Input, proposal: FittingProposal) {
        self.input = input
        self.proposal = proposal
    }
}

extension LayoutInputs: Sendable where Input: Sendable {}

/// A complete layout request: operation, input, proposal, and context.
///
/// Declare a distinct operation type for each unrelated calculation. A parent's input can hold
/// complete child keys, which keeps their structure instead of their hashes or measured sizes;
/// see <doc:CacheContract>.
public typealias LayoutKey<Operation, Input, Context> = RequestKey<Operation, LayoutInputs<Input>, Context>
where Input: Hashable, Context: Hashable
