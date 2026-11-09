/// A labeled dependency value captured for one calculation.
///
/// Labels distinguish roles within a schema, and an original key is never equal to a
/// ``DerivedKey``. `Value` is not deep-copied and must keep stable equality and hashing while
/// the key is retained; see <doc:DependencyDesign>.
public struct OriginalKey<Value>: Hashable where Value: Hashable {
    /// The dependency's role within its schema.
    public let label: String
    /// The captured dependency value.
    public let value: Value

    /// Captures a dependency with its schema label.
    @inlinable
    public init(_ label: String, value: Value) {
        self.label = label
        self.value = value
    }
}

extension OriginalKey {
    /// Returns whether every stored component is equal, including concrete types.
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.label == rhs.label && lhs.value == rhs.value
    }

    /// Hashes the same components that equality compares.
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(value)
    }
}

extension OriginalKey: Sendable where Value: Sendable {}
