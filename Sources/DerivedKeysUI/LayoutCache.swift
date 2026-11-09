import DerivedKeys

/// A main-actor cache for complete layout results such as sizes with child frames.
///
/// Each request is keyed by an operation type, a captured input, the fitting proposal, and a
/// context. The input and context must capture every value the calculation reads, as
/// <doc:CacheContract> describes. Sharing a reference shares entries and recency.
///
/// Entries retain keys and results, never the calculation. The cache observes no views and
/// schedules no layout. Reentering the same cache during a calculation, including reading `count`
/// or removing entries through an alias, fails a precondition.
@MainActor
public final class LayoutCache<Operation, Input, Context, Value> where Input: Hashable, Context: Hashable {
    private var isCalculating = false
    private var storage: MemoizationCache<LayoutKey<Operation, Input, Context>, Value>

    /// The maximum number of retained entries.
    public let capacity: Int

    /// The number of retained entries.
    ///
    /// - Precondition: This cache is not calculating.
    public var count: Int {
        checkAccess()
        return Self.count(of: &storage)
    }

    /// Creates an empty cache that retains at most `capacity` entries.
    ///
    /// Zero capacity disables storage.
    /// - Precondition: `capacity` is nonnegative.
    public init(capacity: Int) {
        self.capacity = capacity
        storage = MemoizationCache(capacity: capacity)
    }

    /// Returns the key for a request without calculating or changing recency.
    ///
    /// Use it to store complete child keys in a parent's input.
    /// - Parameters:
    ///   - input: Stable content values the layout algorithm reads.
    ///   - proposal: The fitting proposal the calculation uses.
    ///   - context: Stable style and environment values the algorithm reads.
    /// - Returns: A key containing the operation, input, proposal, and context.
    public func key(
        for input: Input,
        proposal: FittingProposal,
        context: Context
    ) -> LayoutKey<Operation, Input, Context> {
        LayoutKey(
            dependencies: LayoutInputs(input: input, proposal: proposal),
            context: context
        )
    }

    /// Returns the cached result for the request, calculating it on a miss.
    ///
    /// On a miss, `compute` receives the same input, proposal, and context that form the key;
    /// calculate from those values rather than reading other mutable state. Results are stored as
    /// returned. Hits and successful insertions become most recently used, and a miss at capacity
    /// evicts the least recently used entry. An optional `nil` result is cached as a hit. A
    /// thrown error propagates without insertion or eviction. At zero capacity, every call
    /// calculates without storing.
    /// - Parameters:
    ///   - input: Stable content values captured in the key.
    ///   - proposal: The fitting proposal captured in the key.
    ///   - context: Stable style and environment values captured in the key.
    ///   - compute: The synchronous calculation, called only on a miss. It is not retained,
    ///     and it must not reenter this cache, including through another reference.
    /// - Returns: The retained result on a hit, or the calculation's result on a miss.
    /// - Precondition: This cache is not calculating.
    /// - Complexity: Expected amortized constant-time bookkeeping, excluding hashing,
    ///   equality, and the calculation.
    public func value(
        for input: Input,
        proposal: FittingProposal,
        context: Context,
        compute: @MainActor (Input, FittingProposal, Context) throws -> Value
    ) rethrows -> Value {
        checkAccess()
        let request = key(for: input, proposal: proposal, context: context)
        isCalculating = true
        defer { isCalculating = false }
        return try storage.value(for: request) {
            try compute(request.dependencies.input, request.dependencies.proposal, request.context)
        }
    }

    /// Removes the entry for a request key, if present.
    ///
    /// - Precondition: This cache is not calculating.
    public func removeValue(for key: LayoutKey<Operation, Input, Context>) {
        checkAccess()
        storage.removeValue(for: key)
    }

    /// Removes all entries, releasing their keys and results.
    ///
    /// - Precondition: This cache is not calculating.
    public func removeAll() {
        checkAccess()
        storage.removeAll()
    }

    private func checkAccess() {
        precondition(!isCalculating, "LayoutCache cannot be reentered while a calculation is in progress.")
    }

    // Swift 6.4 can emit an invalid cross-module private metadata reference when copying
    // class-held generic storage to read its count. Read through its address instead.
    private static func count(
        of storage: inout MemoizationCache<LayoutKey<Operation, Input, Context>, Value>
    ) -> Int {
        storage.count
    }
}
