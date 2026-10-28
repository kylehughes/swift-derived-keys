import DerivedKeys

/// A captured dependency projection paired with the effective fitting proposal.
///
/// Equality includes both the input and the exact proposal. Referenced values must
/// retain stable equality and hashing for the lifetime of any key containing them.
public struct LayoutInputs<Input>: Hashable where Input: Hashable {
    /// The layout-relevant values captured by the caller.
    public let input: Input
    /// The effective bounds passed to the layout calculation.
    public let proposal: FittingProposal

    /// Captures the input and the proposal used by a layout calculation.
    public init(input: Input, proposal: FittingProposal) {
        self.input = input
        self.proposal = proposal
    }
}

extension LayoutInputs: Sendable where Input: Sendable {}

/// A complete layout request scoped by operation, version, input, proposal, and context.
///
/// Declare a distinct operation type for unrelated calculations. Parent inputs can retain
/// complete child keys to preserve their structure rather than their hashes or measured sizes.
public typealias LayoutKey<Operation, Input, Context> = RequestKey<Operation, LayoutInputs<Input>, Context>
where Input: Hashable, Context: Hashable
