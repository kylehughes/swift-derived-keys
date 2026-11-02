import DerivedKeys

/// A main-actor bounded LRU cache for complete layout results.
///
/// Assigning or injecting this reference shares the cache and its recency order. Inputs
/// and context must capture every value consumed by the calculation, including any relevant
/// traits. Their equality and hashing must remain stable while stored. Capturing immutable
/// values is the caller's responsibility; main-actor isolation does not freeze mutable aliases.
///
/// Entries retain their keys and results, never the calculation closure. Caller-supplied
/// results may themselves retain references. No views are observed and no layout is scheduled.
/// Reentering this same cache during a calculation is unsupported, including through aliases.
///
/// Lookup and recency bookkeeping take expected amortized constant time apart from hashing
/// and equality. Capacity bounds entry count rather than retained bytes.
@MainActor
public final class LayoutCache<Operation, Input, Context, Value> where Input: Hashable, Context: Hashable {
    private let version: Int
    private var storage: MemoizationCache<LayoutKey<Operation, Input, Context>, Value>

    /// The maximum number of entries retained by the cache.
    public var capacity: Int {
        storage.capacity
    }

    /// The number of entries currently retained by the cache.
    public var count: Int {
        Self.count(of: &storage)
    }

    /// Creates a cache with a fixed request version and nonnegative entry limit.
    ///
    /// Zero capacity disables storage. The default version suffices when the cache is
    /// discarded with its algorithm; use distinct versions for concurrently valid algorithms.
    /// - Precondition: `capacity` is nonnegative.
    public init(capacity: Int, version: Int = 0) {
        self.version = version
        storage = MemoizationCache(capacity: capacity)
    }

    /// Captures a complete request, automatically including the effective proposal.
    ///
    /// Creating a key does not perform or schedule a calculation or alter recency.
    /// - Parameters:
    ///   - input: Stable content values consumed by the layout algorithm.
    ///   - proposal: The effective fitting bounds used by the calculation.
    ///   - context: Stable style and environment values consumed by the algorithm.
    /// - Returns: A key containing the operation, version, input, proposal, and context.
    public func key(
        for input: Input,
        proposal: FittingProposal,
        context: Context
    ) -> LayoutKey<Operation, Input, Context> {
        LayoutKey(
            version: version,
            dependencies: LayoutInputs(input: input, proposal: proposal),
            context: context
        )
    }

    /// Returns a cached layout result, or calculates it from the captured request on a miss.
    ///
    /// The synchronous main-actor callback receives the same input, proposal, and context
    /// stored in the key. Calculate from these values instead of reading uncaptured mutable
    /// state. The callback is not retained. Results are stored without rounding or clamping.
    ///
    /// Hits and successful insertions become most recently used. A successful miss at capacity
    /// evicts the least recently used entry. Optional `nil` results are real hits. A thrown
    /// error propagates without insertion or eviction. At zero capacity every call calculates.
    /// - Parameters:
    ///   - input: Stable content values captured in the request key.
    ///   - proposal: The effective fitting bounds, automatically included in the key.
    ///   - context: Stable style and environment values captured in the request key.
    ///   - compute: The nonescaping synchronous calculation, called only on a miss with
    ///     the keyed input, proposal, and context. It must not read uncaptured variable state
    ///     or reenter this cache, including through another reference.
    /// - Returns: The retained result on a hit, or the callback's result on a successful miss.
    public func value(
        for input: Input,
        proposal: FittingProposal,
        context: Context,
        compute: @MainActor (Input, FittingProposal, Context) throws -> Value
    ) rethrows -> Value {
        let request = key(for: input, proposal: proposal, context: context)
        return try storage.value(for: request) {
            try compute(request.dependencies.input, request.dependencies.proposal, request.context)
        }
    }

    /// Removes the entry for the complete request key, if present.
    public func removeValue(for key: LayoutKey<Operation, Input, Context>) {
        storage.removeValue(for: key)
    }

    /// Removes all entries, releasing the cache's ownership of their keys and results.
    public func removeAll() {
        storage.removeAll()
    }

    // Swift 6.4 can emit an invalid cross-module private metadata reference when copying
    // class-held generic storage to read its count. Read through its address instead.
    private static func count(
        of storage: inout MemoizationCache<LayoutKey<Operation, Input, Context>, Value>
    ) -> Int {
        storage.count
    }
}
