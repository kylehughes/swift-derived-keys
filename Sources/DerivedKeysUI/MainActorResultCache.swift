import DerivedKeys

/// A synchronous main-actor LRU cache with one configured calculation.
///
/// Only selected values form the key. Equal selections reuse results across input instances;
/// input identity is never implicit. Select `\.self` to include an entire hashable input.
/// Use a named tuple to include multiple inputs or calculation parameters.
///
/// Select every variable value read by the calculation. Unselected settings must remain fixed
/// for the cache's lifetime and match across inputs. Selected values must preserve their equality
/// and hashing while stored; project immutable values from mutable references. The calculation
/// must read values consistent with the preceding snapshot. Main-actor isolation does not freeze
/// aliases or observe changes.
///
/// The cache retains its calculation and key-path readers. Entries retain selected values and
/// results without implicitly retaining inputs. Explicit closure captures, reference-valued
/// selections, and results can retain objects. Sharing a reference shares storage and LRU order;
/// independently constructed caches have independent storage, even with equal selections.
/// Reentering the same cache during dependency capture or calculation fails a precondition,
/// including inspection or removal through an alias. Its immutable capacity remains readable.
@MainActor
public final class MainActorResultCache<Input, Value> {
    /// The maximum number of retained results; zero disables storage.
    public let capacity: Int

    private let compute: @MainActor (Input) -> Value
    private var isAccessing = false
    private let reads: [(Input) -> DependencySnapshot]
    private var storage: MemoizationCache<[DependencySnapshot], Value>

    /// The number of retained results.
    public var count: Int {
        checkAccess()
        return Self.count(of: &storage)
    }

    /// Creates a cache from heterogeneous value paths and a retained calculation.
    ///
    /// An empty selection gives every input the same key. The calculation is synchronous,
    /// nonthrowing, and called only on misses. Neither inputs nor results need to be hashable
    /// or sendable; only the selected values must be hashable.
    /// - Parameters:
    ///   - paths: Stable values captured once per path, in order, before lookup or removal.
    ///   - capacity: The maximum number of retained results; zero disables storage.
    ///   - compute: The configured calculation, receiving the current input on a miss.
    /// - Precondition: Capacity is nonnegative.
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

    /// Removes all results, releasing their selected values and results.
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
    /// A changed input can identify a different entry from an earlier lookup.
    /// - Parameter input: The input whose current selected values identify the entry.
    /// - Precondition: No operation on this cache is in progress.
    public func removeValue(for input: Input) {
        checkAccess()
        isAccessing = true
        defer { isAccessing = false }
        storage.removeValue(for: snapshot(of: input))
    }

    /// Returns a cached result or synchronously calculates it on a miss.
    ///
    /// Selection precedes lookup even on hits. Hits promote recency, and insertion at capacity
    /// evicts the least recently used result. Optional `nil` results are hits. At zero capacity
    /// every call calculates. Results are stored without validation or transformation.
    /// - Parameter input: The current input to snapshot and, on a miss, calculate from.
    /// - Returns: The retained result on a hit or the configured calculation's result on a miss.
    /// - Complexity: Expected amortized constant-time bookkeeping, excluding dependency capture,
    ///   hashing, equality, and calculation. Capacity bounds entry count rather than bytes.
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
