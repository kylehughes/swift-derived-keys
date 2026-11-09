/// A labeled composition of captured dependencies.
///
/// Use a small `Hashable` struct, an ordered array, or ``KeyPair`` for the children. Equality
/// compares the label, child structure, and concrete types, and a derived key is never equal to
/// an ``OriginalKey``. Hashing and equality costs scale with the child values they inspect; see
/// <doc:DependencyDesign>.
public struct DerivedKey<Children>: Hashable where Children: Hashable {
    /// The captured children, compared with their own equality and hashing.
    public let children: Children
    /// The composition's role within its schema.
    public let label: String

    /// Captures a labeled composition of children.
    @inlinable
    public init(_ label: String, children: Children) {
        self.children = children
        self.label = label
    }
}

extension DerivedKey {
    /// Returns whether every stored component is equal, including concrete types.
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.children == rhs.children && lhs.label == rhs.label
    }

    /// Hashes the same components that equality compares.
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(children)
        hasher.combine(label)
    }
}

extension DerivedKey: Sendable where Children: Sendable {}
