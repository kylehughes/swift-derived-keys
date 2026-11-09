/// A reusable projection from an input to the dependencies of one operation.
///
/// Capture an input once and pass that same value to both ``key(for:context:version:)`` and the
/// calculation; see <doc:DependencyDesign>. The projection runs synchronously as a
/// side-effect-free read and does not retain the inputs it reads.
///
/// `KeyProjection` is not `Sendable`, and inputs need not be `Sendable`. Swift 6 region
/// isolation confines a projection built from an actor-isolated closure to that actor.
public struct KeyProjection<Operation, Input, Dependencies> where Dependencies: Hashable {
    @usableFromInline
    let project: (Input) -> Dependencies

    /// Creates a projection for an operation type.
    /// - Parameters:
    ///   - operation: The type that names the operation.
    ///   - project: The synchronous function that selects the dependencies from an input.
    public init(operation: Operation.Type, project: @escaping (Input) -> Dependencies) {
        self.project = project
    }

    /// Returns the request key for an input.
    ///
    /// - Parameters:
    ///   - input: The captured input to project.
    ///   - context: The environment values the calculation reads.
    ///   - version: The version that separates concurrently valid algorithms. The default of `0`
    ///     suits a cache discarded on launch.
    /// - Returns: A key scoped to the operation, version, dependencies, and context.
    /// - Complexity: The projection's cost, without hashing the resulting key.
    @inlinable
    public func key<Context>(
        for input: Input,
        context: Context,
        version: Int = 0
    ) -> RequestKey<Operation, Dependencies, Context> where Context: Hashable {
        RequestKey(version: version, dependencies: project(input), context: context)
    }
}
