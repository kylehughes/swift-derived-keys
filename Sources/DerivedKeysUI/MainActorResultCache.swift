import DerivedKeys

/// A main-actor cache that reuses a recipe's result for equal selected values.
///
/// Only the selected key-path values form the key, so inputs with equal selections share a
/// result. Select `\.self` to include a whole hashable input, or pass a named tuple to combine
/// several inputs. Select every variable value the recipe reads; see <doc:CacheContract> for
/// the selection, stability, retention, and clearing rules.
///
/// Sharing a reference shares storage and recency. This cache does not key a fitting proposal.
/// Reentering it during dependency capture or while its recipe runs fails a precondition,
/// including reading ``count`` or removing entries through an alias. ``capacity`` stays
/// readable.
@MainActor
public final class MainActorResultCache<Input, Value> {
    /// The maximum number of retained results.
    ///
    /// Zero disables storage.
    public let capacity: Int

    private let compute: @MainActor (Input) -> Value
    private var isAccessing = false
    private let reads: [(Input) -> DependencySnapshot]
    private var storage: MemoizationCache<[DependencySnapshot], Value>

    /// The number of retained results.
    ///
    /// - Precondition: No operation on this cache is in progress.
    public var count: Int {
        checkAccess()
        return Self.count(of: &storage)
    }

    /// Creates a cache that keys selected values and runs a recipe on a miss.
    ///
    /// An empty selection gives every input the same key. Neither inputs nor results need to be
    /// `Hashable` or `Sendable`; only the selected values must be `Hashable`.
    /// - Parameters:
    ///   - paths: Key paths to the stable values read once in order before lookup or removal.
    ///   - capacity: The maximum number of retained results; zero disables storage.
    ///   - compute: The synchronous recipe, retained by the cache and called with the current
    ///     input on a miss.
    /// - Precondition: `capacity` is nonnegative.
    public init<each Dependency>(
        dependingOn paths: repeat KeyPath<Input, each Dependency>,
        capacity: Int,
        compute: @escaping @MainActor (Input) -> Value
    ) where repeat each Dependency: Hashable {
        precondition(capacity >= 0, "MainActorResultCache capacity must be nonnegative.")
        var reads: [(Input) -> DependencySnapshot] = []
        func append<Component: Hashable>(_ path: KeyPath<Input, Component>) {
            reads.append { input in DependencySnapshot(value: input[keyPath: path]) }
        }
        repeat append(each paths)
        self.capacity = capacity
        self.compute = compute
        self.reads = reads
        storage = MemoizationCache(capacity: capacity)
    }

    /// Removes all results, keeping the key paths and recipe.
    ///
    /// - Precondition: No operation on this cache is in progress.
    public func removeAll() {
        checkAccess()
        isAccessing = true
        defer { isAccessing = false }
        storage.removeAll()
    }

    /// Removes the result for the input's current selected values, if present.
    ///
    /// An input whose selected values have changed since an earlier lookup identifies a
    /// different entry.
    /// - Parameter input: The input whose current selected values identify the entry.
    /// - Precondition: No operation on this cache is in progress.
    public func removeValue(for input: Input) {
        checkAccess()
        isAccessing = true
        defer { isAccessing = false }
        storage.removeValue(for: snapshot(of: input))
    }

    /// Returns the cached result for the input's selected values, running the recipe on a miss.
    ///
    /// Every lookup reads the selected values first, including hits. Hits promote recency, and a
    /// miss at capacity evicts the least recently used result. An optional `nil` result is cached
    /// as a hit, and results are stored as returned. At zero capacity, every call runs the
    /// recipe without storing.
    /// - Parameter input: The current input to read and, on a miss, pass to the recipe.
    /// - Returns: The retained result on a hit, or the recipe's result on a miss.
    /// - Complexity: Expected amortized constant-time bookkeeping, excluding dependency capture,
    ///   hashing, equality, and the recipe.
    /// - Precondition: No operation on this cache is in progress.
    public func value(for input: Input) -> Value {
        checkAccess()
        isAccessing = true
        defer { isAccessing = false }
        let key = snapshot(of: input)
        let compute = compute
        return storage.value(for: key) { compute(input) }
    }

    // Read through the storage address to avoid Swift 6.4 cross-module metadata references.
    private static func count(of storage: inout MemoizationCache<[DependencySnapshot], Value>) -> Int {
        storage.count
    }

    private func checkAccess() {
        precondition(!isAccessing, "MainActorResultCache cannot be reentered while an operation is in progress.")
    }

    private func snapshot(of input: Input) -> [DependencySnapshot] {
        reads.map { $0(input) }
    }
}
