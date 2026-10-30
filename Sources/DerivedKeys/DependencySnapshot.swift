/// Captured heterogeneous values with structural equality.
///
/// Snapshots contain complete values and structure, never provider closures or
/// source graph nodes. Equality preserves concrete value types, labels, child
/// order, multiplicity, and nesting. Captured values must have stable equality and
/// hashing; mutable references require an explicit immutable projection.
/// The erased representation has no Sendable conformance. Prefer typed keys
/// for transferable values.
public struct DependencySnapshot: Hashable {
    /// The largest supported number of nodes on a root-to-leaf path.
    ///
    /// This bound protects recursive equality, hashing, and teardown.
    public static var maximumDepth: Int {
        64
    }

    let depth: Int
    let node: Node

    /// Creates a snapshot retaining a complete value and its concrete type.
    ///
    /// The snapshot has an empty label and equals an equivalent empty-label
    /// ``KeySource`` snapshot. Values must preserve their equality and hashing
    /// through any mutable aliases; this initializer does not deep-copy them.
    public init<Value>(value: Value) where Value: Hashable {
        self.init(label: "", value: value)
    }

    /// Creates an ordered composition, preserving each child's boundary.
    ///
    /// Empty compositions are valid and have depth one. The composition has an
    /// empty label and equals an equivalent empty-label ``KeySource`` snapshot.
    /// - Throws: ``ConstructionError/maximumDepthExceeded`` for a path longer than
    ///   ``maximumDepth``. Immutable construction cannot introduce cycles.
    /// - Complexity: O(n) in the number of immediate children.
    public init(children: [Self]) throws {
        self.init(node: .derived(label: "", children: children))
        guard depth <= Self.maximumDepth else {
            throw ConstructionError.maximumDepthExceeded
        }
    }

    init<Value>(label: String, value: Value) where Value: Hashable {
        self.init(
            node: .original(
                label: label,
                type: ObjectIdentifier(Value.self),
                value: AnyHashable(ConcreteValue(value: value))
            )
        )
    }

    init(node: Node) {
        self.node = node
        switch node {
        case .original:
            depth = 1
        case .derived(_, let children):
            depth = children.reduce(1) { max($0, $1.depth + 1) }
        }
    }
}

extension DependencySnapshot {
    /// An invalid snapshot composition request.
    public enum ConstructionError: Error, Equatable {
        /// The new composition would exceed the supported depth.
        case maximumDepthExceeded
    }
}

extension DependencySnapshot {
    // Erase the wrapper so AnyHashable preserves Value's concrete Hashable
    // operations instead of applying collection element erasure or bridging.
    private struct ConcreteValue<Value>: Hashable where Value: Hashable {
        let value: Value
    }

    indirect enum Node: Hashable {
        case original(label: String, type: ObjectIdentifier, value: AnyHashable)
        case derived(label: String, children: [DependencySnapshot])
    }
}
