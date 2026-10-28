/// A labeled, structural composition of captured dependencies.
///
/// Use a small `Hashable` struct, an ordered array, or ``KeyPair`` for children.
/// Child structure and concrete types are part of equality. A derived key is
/// distinct from an ``OriginalKey`` even when their labels and values match.
/// Hashing and equality cost as much as the inspected child values.
public struct DerivedKey<Children>: Hashable where Children: Hashable {
    /// The captured children, retaining their own equality semantics.
    public let children: Children
    /// The composition's role within its schema.
    public let label: String

    /// Captures a composition without evaluating live providers.
    public init(_ label: String, children: Children) {
        self.children = children
        self.label = label
    }
}

extension DerivedKey: Sendable where Children: Sendable {}
