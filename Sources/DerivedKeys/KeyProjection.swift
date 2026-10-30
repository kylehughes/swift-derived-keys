/// A reusable selection of the inputs that affect one operation.
///
/// Capture an input snapshot once, then use it for both projection and calculation.
/// Projection is synchronous and runs when ``key(for:context:version:)`` is called.
/// It must be a side-effect-free read and must not suspend or recursively evaluate
/// itself. Actor-owned clients capture their state within that actor's isolation.
/// This projection neither retains inputs after a call nor requires them to be Sendable.
public struct KeyProjection<Operation, Input, Dependencies> where Dependencies: Hashable {
    private let project: (Input) -> Dependencies

    /// Creates a projection for a nominal operation type.
    public init(operation: Operation.Type, project: @escaping @Sendable (Input) -> Dependencies) {
        self.project = project
    }

    /// Creates a projection backed by a nonisolated reader without requiring Sendable state.
    public init<Provider>(operation: Operation.Type, provider: Provider)
    where Provider: KeyValueProvider, Provider.Input == Input, Provider.Value == Dependencies {
        project = { input in
            provider.value(for: input)
        }
    }

    /// Evaluates the projection against an explicitly captured input.
    ///
    /// - Complexity: The projection's cost, without hashing the resulting key.
    public func key<Context>(
        for input: Input,
        context: Context,
        version: Int = 0
    ) -> RequestKey<Operation, Dependencies, Context> where Context: Hashable {
        RequestKey(version: version, dependencies: project(input), context: context)
    }
}
