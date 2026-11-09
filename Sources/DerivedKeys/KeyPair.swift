/// Two ordered dependency values, each keeping its concrete type.
///
/// Use a domain struct for larger fixed schemas, an array for homogeneous ordered collections,
/// or ``KeySource`` for heterogeneous runtime composition. See <doc:DependencyDesign> for
/// choosing complete, stable dependencies.
public struct KeyPair<First, Second>: Hashable where First: Hashable, Second: Hashable {
    /// The first dependency.
    public let first: First
    /// The second dependency.
    public let second: Second

    /// Captures two dependencies in order.
    @inlinable
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }
}

extension KeyPair {
    /// Returns whether every stored component is equal, including concrete types.
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.first == rhs.first && lhs.second == rhs.second
    }

    /// Hashes the same components that equality compares.
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(first)
        hasher.combine(second)
    }
}

extension KeyPair: Sendable where First: Sendable, Second: Sendable {}
