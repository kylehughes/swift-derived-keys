/// Two ordered dependency values with independently preserved concrete types.
///
/// Use a domain struct for larger fixed schemas. Use an array for homogeneous
/// ordered collections, or ``KeySource`` for heterogeneous runtime composition.
public struct KeyPair<First, Second>: Hashable where First: Hashable, Second: Hashable {
    /// The first dependency.
    public let first: First
    /// The second dependency.
    public let second: Second

    /// Captures two dependencies in the specified order.
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
}

extension KeyPair: Sendable where First: Sendable, Second: Sendable {}
