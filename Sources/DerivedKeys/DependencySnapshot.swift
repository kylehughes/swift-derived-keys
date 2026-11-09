/// Heterogeneous values captured for one request, compared by value and structure.
///
/// A snapshot holds complete values and their structure, never provider closures or source
/// graph nodes. Equality compares concrete value types, labels, child order, multiplicity,
/// and nesting. Captured values must keep stable equality and hashing, so project mutable
/// references into immutable values first; see <doc:DependencyDesign>.
///
/// A snapshot is not `Sendable`. Prefer typed keys for values that cross isolation boundaries.
public struct DependencySnapshot: Hashable {
    /// The largest supported number of nodes on a root-to-leaf path.
    ///
    /// The bound keeps recursive equality, hashing, and teardown safe.
    public static var maximumDepth: Int {
        64
    }

    let depth: Int
    @usableFromInline
    let node: Node

    /// Creates a snapshot of one value, keeping its concrete type.
    ///
    /// The snapshot has an empty label and equals an equivalent empty-label ``KeySource``
    /// snapshot. The value is not deep-copied, so it must keep stable equality and hashing.
    @inlinable
    public init<Value>(value: Value) where Value: Hashable {
        self.init(label: "", value: value)
    }

    /// Creates an ordered composition of snapshots, keeping each child's boundary.
    ///
    /// An empty composition is valid. The composition has an empty label and equals an
    /// equivalent empty-label ``KeySource`` snapshot.
    /// - Parameter children: The snapshots to compose, in order.
    /// - Throws: ``ConstructionError/maximumDepthExceeded`` for a path longer than
    ///   ``maximumDepth``.
    /// - Complexity: O(n) in the number of immediate children.
    public init(children: [Self]) throws {
        self.init(node: .derived(label: "", children: children))
        guard depth <= Self.maximumDepth else {
            throw ConstructionError.maximumDepthExceeded
        }
    }

    @inlinable
    init<Value>(label: String, value: Value) where Value: Hashable {
        self.init(node: .original(label: label, value: ConcreteBox(value)))
    }

    @usableFromInline
    init(node: Node) {
        self.node = node
        switch node {
        case .original:
            depth = 1
        case .derived(_, let children):
            depth = children.reduce(1) { max($0, $1.depth + 1) }
        }
    }

    /// Returns whether both snapshots hold equal values and structure, including concrete types.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.node == rhs.node
    }

    /// Hashes the components that equality compares.
    public func hash(into hasher: inout Hasher) {
        node.hash(into: &hasher)
    }
}

extension DependencySnapshot {
    /// An error from composing a snapshot.
    public enum ConstructionError: Error, Equatable {
        /// The new composition would exceed the supported depth.
        case maximumDepthExceeded
    }
}

extension DependencySnapshot {
    // A class box preserves Value's concrete Hashable operations without the
    // element erasure or bridging that AnyHashable applies to collections.
    @usableFromInline
    class ErasedBox {
        @usableFromInline
        init() {}

        @usableFromInline
        func isEqual(to other: ErasedBox) -> Bool {
            fatalError("Subclasses must override isEqual(to:).")
        }

        @usableFromInline
        func hash(into hasher: inout Hasher) {
            fatalError("Subclasses must override hash(into:).")
        }
    }

    @usableFromInline
    final class ConcreteBox<Value>: ErasedBox where Value: Hashable {
        @usableFromInline
        let value: Value

        @inlinable
        init(_ value: Value) {
            self.value = value
        }

        @inlinable
        override func isEqual(to other: ErasedBox) -> Bool {
            guard ObjectIdentifier(type(of: self)) == ObjectIdentifier(type(of: other)) else {
                return false
            }

            return value == unsafeDowncast(other, to: ConcreteBox<Value>.self).value
        }

        @inlinable
        override func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(type(of: self)))
            hasher.combine(value)
        }
    }

    @usableFromInline
    enum Node: Hashable {
        case original(label: String, value: ErasedBox)
        case derived(label: String, children: [DependencySnapshot])

        @usableFromInline
        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.original(let leftLabel, let leftValue), .original(let rightLabel, let rightValue)):
                return leftLabel == rightLabel && (leftValue === rightValue || leftValue.isEqual(to: rightValue))
            case (.derived(let leftLabel, let leftChildren), .derived(let rightLabel, let rightChildren)):
                return leftLabel == rightLabel && leftChildren == rightChildren
            default:
                return false
            }
        }

        @usableFromInline
        func hash(into hasher: inout Hasher) {
            switch self {
            case .original(let label, let value):
                hasher.combine(0 as UInt8)
                hasher.combine(label)
                value.hash(into: &hasher)
            case .derived(let label, let children):
                hasher.combine(1 as UInt8)
                hasher.combine(label)
                hasher.combine(children)
            }
        }
    }
}
