/// A labeled dependency value captured for one calculation.
///
/// `Value` must keep stable equality and hashing for the lifetime of this key.
/// For mutable reference state, capture an immutable projection first; this type
/// does not deep-copy arbitrary values. Labels distinguish roles within a schema.
public struct OriginalKey<Value>: Hashable where Value: Hashable {
    /// The dependency's role within its schema.
    public let label: String
    /// The captured dependency value.
    public let value: Value

    /// Captures a dependency with its schema label.
    public init(_ label: String, value: Value) {
        self.label = label
        self.value = value
    }
}

extension OriginalKey: Sendable where Value: Sendable {}
