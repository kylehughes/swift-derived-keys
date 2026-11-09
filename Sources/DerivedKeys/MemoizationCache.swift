/// A bounded cache from keys to values that evicts the least recently used entry.
///
/// The cache owns its keys and values and never retains a calculation closure. Keys must
/// keep stable equality and hashing while stored; see <doc:DependencyDesign>. The cache is a
/// value type, and copying it does not deep-copy references held by keys or values.
///
/// Dictionary indexing and recency bookkeeping take expected amortized constant time, apart from
/// hashing and equality. The first mutation after a copy can be linear in the number of allocated
/// entries. Reentering the same cache during `compute` is unsupported. The conditional
/// `Sendable` conformance does not provide shared synchronization.
public struct MemoizationCache<Key, Value> where Key: Hashable {
    /// The maximum number of entries.
    ///
    /// Capacity limits entries, not retained bytes.
    public let capacity: Int

    @usableFromInline
    var entries: [Entry?] = []
    @usableFromInline
    var freeIndices: [Int] = []
    @usableFromInline
    var indices: [Key: Int] = [:]
    @usableFromInline
    var leastRecentIndex: Int?
    @usableFromInline
    var mostRecentIndex: Int?

    /// Creates an empty cache with the given entry limit.
    ///
    /// Zero capacity disables storage while still running the calculation on every request.
    /// - Precondition: `capacity` is nonnegative.
    @inlinable
    public init(capacity: Int) {
        precondition(capacity >= 0, "Cache capacity must be nonnegative.")
        self.capacity = capacity
    }

    /// The number of stored entries.
    @inlinable
    public var count: Int {
        indices.count
    }

    /// Removes all entries, releasing their keys and values.
    @inlinable
    public mutating func removeAll() {
        entries = []
        freeIndices = []
        indices = [:]
        leastRecentIndex = nil
        mostRecentIndex = nil
    }

    /// Removes the entry for `key`, if present.
    /// - Parameter key: The key to remove.
    @inlinable
    public mutating func removeValue(for key: Key) {
        guard let index = indices.removeValue(forKey: key) else {
            return
        }

        unlink(index)
        entries[index] = nil
        freeIndices.append(index)
    }

    /// Returns the cached value for `key`, computing and storing it on a miss.
    ///
    /// Hits and successful insertions become most recently used, and a miss at capacity evicts
    /// the least recently used entry. A thrown error propagates without inserting or evicting.
    /// An optional `nil` result is stored and counts as a hit. At zero capacity every call
    /// computes without storing.
    /// - Parameters:
    ///   - key: The complete key to look up.
    ///   - compute: The calculation, called only on a miss.
    /// - Returns: The retained value on a hit, or the calculation's result on a miss.
    @inlinable
    public mutating func value(for key: Key, compute: () throws -> Value) rethrows -> Value {
        if let index = indices[key] {
            let value = entry(at: index).value
            promote(index)

            return value
        }

        let value = try compute()
        guard capacity > 0 else {
            return value
        }

        if count == capacity, let index = leastRecentIndex {
            removeValue(for: entry(at: index).key)
        }

        let index: Int
        let entry = Entry(key: key, value: value, next: nil, previous: mostRecentIndex)
        if let freeIndex = freeIndices.popLast() {
            index = freeIndex
            entries[index] = entry
        } else {
            index = entries.count
            entries.append(entry)
        }

        indices[key] = index
        if let mostRecentIndex {
            entries[mostRecentIndex]?.next = index
        } else {
            leastRecentIndex = index
        }

        mostRecentIndex = index

        return value
    }

    @inlinable
    func entry(at index: Int) -> Entry {
        guard let entry = entries[index] else {
            preconditionFailure("Cache recency links must refer to occupied entries.")
        }

        return entry
    }

    @inlinable
    mutating func promote(_ index: Int) {
        guard index != mostRecentIndex else {
            return
        }

        unlink(index)
        entries[index]?.previous = mostRecentIndex
        entries[index]?.next = nil
        if let mostRecentIndex {
            entries[mostRecentIndex]?.next = index
        }

        mostRecentIndex = index
    }

    @inlinable
    mutating func unlink(_ index: Int) {
        let entry = entry(at: index)
        if let previous = entry.previous {
            entries[previous]?.next = entry.next
        } else {
            leastRecentIndex = entry.next
        }

        if let next = entry.next {
            entries[next]?.previous = entry.previous
        } else {
            mostRecentIndex = entry.previous
        }
    }
}

extension MemoizationCache: Sendable where Key: Sendable, Value: Sendable {}

extension MemoizationCache {
    @usableFromInline
    struct Entry {
        @usableFromInline
        let key: Key
        @usableFromInline
        let value: Value
        @usableFromInline
        var next: Int?
        @usableFromInline
        var previous: Int?

        @inlinable
        init(key: Key, value: Value, next: Int?, previous: Int?) {
            self.key = key
            self.value = value
            self.next = next
            self.previous = previous
        }
    }
}

extension MemoizationCache.Entry: Sendable where Key: Sendable, Value: Sendable {}
