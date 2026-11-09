/// A bounded cache that reuses a recipe's result for equal selected values.
///
/// Only the selected key-path values determine reuse, so the recipe must return interchangeable
/// results whenever they match. Use `\.self` to select a whole hashable input, or pass a named
/// tuple to combine several inputs. Passing no key paths gives every request the same key. See
/// <doc:DependencyDesign> for choosing complete, stable selections.
///
/// The cache is a value type: copies mutate their entries independently without deep-copying
/// captured references. It retains its recipe and key-path readers, while entries retain only
/// selected values and results, not inputs. It is not `Sendable` and provides no shared
/// synchronization. Reentering the same cache while its recipe is running is unsupported.
public struct ResultCache<Input, Value> {
    @usableFromInline
    let compute: (Input) -> Value
    @usableFromInline
    let readers: [(Input) -> DependencySnapshot]
    @usableFromInline
    var storage: MemoizationCache<[DependencySnapshot], Value>

    /// The maximum number of entries.
    ///
    /// Capacity limits entries, not retained bytes.
    @inlinable
    public var capacity: Int { storage.capacity }

    /// The number of stored entries.
    @inlinable
    public var count: Int { storage.count }

    /// Creates an empty cache that keys selected values and runs a recipe on a miss.
    ///
    /// Key paths and the recipe are ordinary non-`Sendable` closures, and inputs, selected
    /// values, and results need not be `Sendable`. Swift 6 region isolation confines a cache
    /// built from actor-isolated key paths or closures to that actor, so a main-actor type can
    /// own one directly.
    ///
    /// - Parameters:
    ///   - paths: Key paths to the ordered values that determine result reuse.
    ///   - capacity: The maximum number of entries. Zero disables storage.
    ///   - compute: The synchronous recipe, called once on each miss.
    /// - Precondition: `capacity` is nonnegative.
    public init<each Dependency>(
        dependingOn paths: repeat KeyPath<Input, each Dependency>,
        capacity: Int,
        compute: @escaping (Input) -> Value
    ) where repeat each Dependency: Hashable {
        var readers: [(Input) -> DependencySnapshot] = []
        func append<SelectedValue>(_ path: KeyPath<Input, SelectedValue>)
        where SelectedValue: Hashable {
            readers.append { input in DependencySnapshot(value: input[keyPath: path]) }
        }
        repeat append(each paths)
        self.readers = readers
        self.compute = compute
        storage = MemoizationCache(capacity: capacity)
    }

    /// Removes all entries, keeping the key paths and recipe.
    @inlinable
    public mutating func removeAll() {
        storage.removeAll()
    }

    /// Removes the entry for the input's current selected values, if present.
    ///
    /// This reads each selected value once and never runs the recipe.
    /// - Parameter input: The input whose current selected values identify the entry.
    /// - Complexity: Dependency capture, hashing, and equality work plus expected
    ///   amortized O(1) bookkeeping; the first mutation after a copy may be O(n).
    @inlinable
    public mutating func removeValue(for input: Input) {
        storage.removeValue(for: readers.map { $0(input) })
    }

    /// Returns the cached result for the input's selected values, running the recipe on a miss.
    ///
    /// A lookup reads each selected value once in order and, on a miss, passes the same input to
    /// the recipe. Hits and insertions become most recently used, and an insertion at capacity
    /// evicts the least recently used entry. An optional `nil` result is cached as a hit. At zero
    /// capacity, every call runs the recipe without storing.
    ///
    /// - Parameter input: The input to read and, on a miss, pass to the recipe.
    /// - Returns: The retained result on a hit, or the recipe's result on a miss.
    /// - Complexity: Dependency capture, hashing, and equality work plus expected
    ///   amortized O(1) bookkeeping and the recipe on a miss. The first mutation after
    ///   a copy may be O(n) in the number of allocated entries.
    @inlinable
    public mutating func value(for input: Input) -> Value {
        let key = readers.map { $0(input) }
        let compute = compute
        return storage.value(for: key) { compute(input) }
    }
}
