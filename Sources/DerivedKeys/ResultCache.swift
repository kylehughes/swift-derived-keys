/// A bounded, value-semantic cache configured with selected inputs and one computation.
///
/// Only the selected key-path values determine reuse. The computation must produce
/// interchangeable results whenever those values are equal; any other inputs it reads
/// must stay fixed for the cache's lifetime. Use `\.self` to select a complete scalar
/// value, or named tuple members to combine inputs. No dependencies means one shared key.
///
/// Selected values retain their complete concrete values and types. Their equality and
/// hashing must remain stable while cached; project immutable values from mutable aliases.
/// Entries do not implicitly retain inputs, but reference-valued dependencies and results
/// can retain them. The cache retains its configured computation and its captures.
///
/// Copies mutate their entries independently without deep-copying captured references.
/// This type is not Sendable and provides no shared synchronization. Reentering the same
/// cache during computation is unsupported because mutation requires exclusive access.
public struct ResultCache<Input, Value> {
    private let compute: (Input) -> Value
    private let readers: [(Input) -> DependencySnapshot]
    private var storage: MemoizationCache<[DependencySnapshot], Value>

    /// The maximum number of entries, rather than a limit on retained bytes.
    public var capacity: Int { storage.capacity }

    /// The number of currently stored entries.
    public var count: Int { storage.count }

    /// Creates an empty cache with a fixed dependency selection and computation.
    ///
    /// Inputs and results need not be Hashable or Sendable. Sendable key paths and
    /// computation prevent implicit access to actor-isolated state; they do not require
    /// the selected values themselves to be Sendable or assert computation purity.
    ///
    /// - Parameters:
    ///   - paths: The ordered values that fully determine result reuse.
    ///   - capacity: The maximum number of entries. Zero disables storage.
    ///   - compute: The synchronous computation invoked once on each miss.
    /// - Precondition: `capacity` is nonnegative.
    public init<each Dependency>(
        dependingOn paths: repeat (KeyPath<Input, each Dependency> & Sendable),
        capacity: Int,
        compute: @escaping @Sendable (Input) -> Value
    ) where repeat each Dependency: Hashable {
        var readers: [(Input) -> DependencySnapshot] = []
        func append<SelectedValue>(_ path: KeyPath<Input, SelectedValue> & Sendable)
        where SelectedValue: Hashable {
            readers.append { input in DependencySnapshot(value: input[keyPath: path]) }
        }
        repeat append(each paths)
        self.readers = readers
        self.compute = compute
        storage = MemoizationCache(capacity: capacity)
    }

    /// Removes all entries, releasing their keys and values while retaining configuration.
    public mutating func removeAll() {
        storage.removeAll()
    }

    /// Removes the entry matching the input's current selected values, if present.
    ///
    /// This reads each selected value once and never invokes the computation.
    /// - Complexity: Dependency capture, hashing, and equality work plus expected
    ///   amortized O(1) bookkeeping; the first mutation after a copy may be O(n).
    public mutating func removeValue(for input: Input) {
        storage.removeValue(for: readers.map { $0(input) })
    }

    /// Returns the cached result or computes and stores a result on a miss.
    ///
    /// Each selected value is read once before lookup. A miss passes the same input to
    /// the computation. Callers must keep reference-backed inputs consistent throughout
    /// the call. Hits and insertions become most recently used; insertion at capacity
    /// evicts the least recently used entry. Optional `nil` results are real hits.
    /// At zero capacity every call computes without storing a result.
    ///
    /// - Complexity: Dependency capture, hashing, and equality work plus expected
    ///   amortized O(1) bookkeeping and computation on a miss. The first mutation after
    ///   a copy may be O(n) in the number of allocated entries.
    public mutating func value(for input: Input) -> Value {
        let key = readers.map { $0(input) }
        let compute = compute
        return storage.value(for: key) { compute(input) }
    }
}
