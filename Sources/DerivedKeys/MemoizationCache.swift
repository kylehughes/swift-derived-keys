/// A bounded, value-semantic cache that evicts the least recently used entry.
///
/// The cache owns its stored keys and values, but never retains a calculation closure.
/// Keys must have stable equality and hashing while stored. Values and keys containing
/// references must preserve their promised meaning through any external aliases; copying
/// the cache does not deep-copy those references.
///
/// Dictionary indexing and recency bookkeeping take expected amortized constant time,
/// apart from hashing and equality. Standard-library copy-on-write storage makes the
/// first mutation after a copy potentially linear in the number of allocated entries.
/// Reentering the same cache during `compute` is unsupported. Mutation requires exclusive
/// access; the cache's conditional `Sendable` conformance does not provide shared synchronization.
public struct MemoizationCache<Key, Value> where Key: Hashable {
    /// The maximum number of entries, rather than a limit on retained bytes.
    public let capacity: Int

    private var entries: [Entry?] = []
    private var freeIndices: [Int] = []
    private var indices: [Key: Int] = [:]
    private var leastRecentIndex: Int?
    private var mostRecentIndex: Int?

    /// Creates an empty cache with the given entry limit.
    ///
    /// - Precondition: `capacity` is nonnegative. Zero disables storage.
    public init(capacity: Int) {
        precondition(capacity >= 0, "Cache capacity must be nonnegative.")
        self.capacity = capacity
    }

    /// The number of currently stored entries.
    public var count: Int {
        indices.count
    }

    /// Removes all entries, releasing the cache's ownership of their keys and values.
    public mutating func removeAll() {
        entries = []
        freeIndices = []
        indices = [:]
        leastRecentIndex = nil
        mostRecentIndex = nil
    }

    /// Removes the entry for `key`, if present.
    public mutating func removeValue(for key: Key) {
        guard let index = indices.removeValue(forKey: key) else {
            return
        }

        unlink(index)
        entries[index] = nil
        freeIndices.append(index)
    }

    /// Returns a cached value, or computes and stores a result on a miss.
    ///
    /// Hits and successful insertions become most recently used. A successful miss at
    /// capacity evicts the least recently used entry. A thrown error propagates without
    /// inserting or evicting an entry. An optional `nil` result is stored as a real hit.
    /// At zero capacity, every call computes a result without storing it.
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

    private func entry(at index: Int) -> Entry {
        guard let entry = entries[index] else {
            preconditionFailure("Cache recency links must refer to occupied entries.")
        }

        return entry
    }

    private mutating func promote(_ index: Int) {
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

    private mutating func unlink(_ index: Int) {
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
    fileprivate struct Entry {
        let key: Key
        let value: Value
        var next: Int?
        var previous: Int?
    }
}

extension MemoizationCache.Entry: Sendable where Key: Sendable, Value: Sendable {}
