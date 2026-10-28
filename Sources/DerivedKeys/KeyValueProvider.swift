/// A synchronous nonisolated reader that can own non-Sendable state.
///
/// Use this protocol when a closure cannot express the ownership of a live source.
/// A provider need not be Sendable. Its state must stay within one mutation owner;
/// `value(for:)` must read without I/O, suspension, mutation, or recursive evaluation.
/// Actor-isolated state should be captured into an explicit input snapshot instead.
public nonisolated protocol KeyValueProvider<Input, Value>: SendableMetatype {
    /// The explicit input supplied to each evaluation.
    associatedtype Input
    /// The immutable dependency projection returned by a read.
    associatedtype Value: Hashable

    /// Reads a dependency from the current input and any owner-confined state.
    nonisolated func value(for input: Input) -> Value
}
