/// An immutable key scoped to a nominal operation, version, dependencies, and context.
///
/// Declare a distinct empty enum for each unrelated operation. `Operation` is a
/// type token, never a stored instance. Separate specializations remain distinct
/// when erased to `AnyHashable`. A label alone does not isolate operations.
///
/// Equal keys must imply interchangeable results: capture every input the
/// calculation reads, including its effective environment. Hashes are process-local
/// dictionary accelerators, not persisted identifiers or collision-free fingerprints.
public struct RequestKey<Operation, Dependencies, Context>: Hashable
where Dependencies: Hashable, Context: Hashable {
    /// The captured calculation environment.
    public let context: Context
    /// The captured dependency projection.
    public let dependencies: Dependencies
    /// A version separating concurrently valid algorithms.
    public let version: Int

    /// Captures the complete semantic request.
    ///
    /// The default version is enough for caches discarded when the process exits.
    /// Dependencies and context must retain stable equality and hashing. Calculation
    /// must use the same captured inputs; the key does not synchronize a model.
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

extension RequestKey: Sendable where Dependencies: Sendable, Context: Sendable {}
