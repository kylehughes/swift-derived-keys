/// A key for one request: operation, version, dependencies, and context.
///
/// Declare a distinct empty enum for each unrelated operation. `Operation` is a type token that
/// is never stored, and a label alone does not separate operations. Capture every input and
/// environment value the calculation reads so equal keys imply interchangeable results. Hashes
/// are process-local and are not identifiers; see <doc:DependencyDesign>.
public struct RequestKey<Operation, Dependencies, Context>: Hashable
where Dependencies: Hashable, Context: Hashable {
    /// The environment values the calculation reads.
    public let context: Context
    /// The values the calculation reads from its input.
    public let dependencies: Dependencies
    /// The version that separates concurrently valid algorithms.
    public let version: Int

    /// Creates a request key for an operation, its dependencies, and its context.
    ///
    /// The default `version` of `0` suits a cache discarded when the process exits.
    /// `dependencies` and `context` must keep stable equality and hashing, and the calculation
    /// must read from those same captured values; the key does not synchronize a model.
    /// - Parameters:
    ///   - operation: The type that names the operation.
    ///   - version: The version that separates concurrently valid algorithms.
    ///   - dependencies: The values the calculation reads from its input.
    ///   - context: The environment values the calculation reads.
    @inlinable
    public init(
        operation: Operation.Type = Operation.self,
        version: Int = 0,
        dependencies: Dependencies,
        context: Context
    ) {
        self.context = context
        self.dependencies = dependencies
        self.version = version
    }
}

extension RequestKey {
    /// Returns whether every stored component is equal, including concrete types.
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.version == rhs.version && lhs.dependencies == rhs.dependencies && lhs.context == rhs.context
    }

    /// Hashes the same components that equality compares.
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(version)
        hasher.combine(dependencies)
        hasher.combine(context)
    }
}

extension RequestKey: Sendable where Dependencies: Sendable, Context: Sendable {}
