import CoreGraphics
import DerivedKeys
import DerivedKeysUIKit

/// A synchronous main-actor LRU cache with one configured size-measurement recipe.
///
/// Roots with equal dependency snapshots and effective fitting proposals reuse cached sizes.
/// Select every variable value read by the recipe, including environment values. Any measurement
/// settings you omit must stay fixed for the cache's lifetime and match across all roots sharing
/// this cache; select settings that vary or use separate caches. Child descriptions contribute
/// their captured values to the parent's snapshot, not their measured sizes or proposals.
///
/// Measurement must read values consistent with the preceding snapshot. Main-actor isolation
/// does not prevent mutations through aliases.
///
/// Entries retain snapshots and sizes without implicitly retaining roots. The cache retains
/// its measurement closure for its lifetime, including any objects the closure captures strongly.
///
/// Sharing a reference shares result storage and LRU recency order. Sizes are stored without
/// validation, rounding, or clamping. Reentering the same cache during measurement, including
/// inspecting or removing entries through an alias, fails a precondition.
@MainActor
public final class SizeCache<Root>: SizeDependencies<Root> {
    /// The maximum number of retained results.
    ///
    /// Zero disables storage.
    public let capacity: Int

    private var isMeasuring = false
    private let measure: @MainActor (Root, CGSize) -> CGSize
    private var storage: MemoizationCache<RequestKey<SizeOperation, DependencySnapshot, SizeContext>, CGSize>

    /// The number of retained results.
    public var count: Int {
        checkAccess()
        return Self.count(of: &storage)
    }

    /// Creates a cache from heterogeneous value paths and ordered child descriptions.
    ///
    /// Both dependency lists may be empty. Local values precede children in the snapshot.
    /// Child storage and measurement closures are not retained by these descriptions.
    /// The recipe must capture the child caches or bound handles it measures.
    ///
    /// - Parameters:
    ///   - paths: Stable hashable values read from each root before lookup.
    ///   - children: Ordered dependency descriptions that contribute to every snapshot,
    ///     whether or not the recipe measures those children.
    ///   - capacity: The maximum number of retained sizes; zero disables storage.
    ///   - measure: The retained synchronous recipe, called on a miss with the current root
    ///     and normalized proposal. Measure children or use an uncached routine when the
    ///     root's `sizeThatFits(_:)` override calls this cache; calling that override here
    ///     would reenter the cache.
    /// - Precondition: Capacity is nonnegative and the composed depth is at most `maximumDepth`.
    public init<each Value>(
        dependingOn paths: repeat KeyPath<Root, each Value>,
        children: SizeDependencies<Root>...,
        capacity: Int,
        measure: @escaping @MainActor (Root, CGSize) -> CGSize
    ) where repeat each Value: Hashable {
        precondition(capacity >= 0, "SizeCache capacity must be nonnegative.")
        var reads: [(Root) -> DependencySnapshot] = []
        func append<Component: Hashable>(_ path: KeyPath<Root, Component>) {
            reads.append { root in DependencySnapshot(value: root[keyPath: path]) }
        }
        repeat append(each paths)
        let depth = 1 + max(reads.isEmpty ? 0 : 1, children.map { $0.depth }.max() ?? 0)
        precondition(depth <= DependencySnapshot.maximumDepth, "SizeCache dependency depth exceeds maximumDepth.")
        let captures = reads + children.map { $0.capture }
        self.capacity = capacity
        self.measure = measure
        storage = MemoizationCache(capacity: capacity)
        super
            .init(depth: depth) { root in
                do {
                    return try DependencySnapshot(children: captures.map { $0(root) })
                } catch {
                    preconditionFailure("SizeCache's checked immutable dependency description exceeded maximumDepth.")
                }
            }
    }

    /// Removes all local results without clearing any child cache.
    public func removeAll() {
        checkAccess()
        storage.removeAll()
    }

    /// Removes the local result for the root's current snapshot and effective proposal.
    ///
    /// A changed root may describe a different entry from an earlier measurement.
    /// Children are captured but their result storage is not accessed or cleared.
    /// - Parameters:
    ///   - root: The root whose current selected values identify the entry.
    ///   - size: The fitting proposal used for the entry, normalized as during lookup.
    public func removeSize(of root: Root, toFit size: CGSize) {
        checkAccess()
        storage.removeValue(for: key(of: root, toFit: size))
    }

    /// Returns a cached size or synchronously measures the root on a miss.
    ///
    /// Both finite nonnegative proposal axes participate exactly in the key. Signed zero
    /// is normalized; greatest finite magnitude denotes an unconstrained axis. The recipe
    /// receives this normalized proposal. Hits promote recency; insertion at capacity evicts
    /// the least recently used result. At zero capacity every request measures.
    ///
    /// Snapshot evaluation precedes lookup even on hits. Parent hits never look up child
    /// results. Expected lookup bookkeeping is amortized constant time, excluding snapshot
    /// evaluation, hashing, equality, and measurement.
    /// - Parameters:
    ///   - root: The current root to snapshot and, on a miss, measure. Its identity is not
    ///     implicitly part of the key, and the cache does not implicitly retain it.
    ///   - size: The fitting proposal in points, with greatest finite magnitude denoting
    ///     an unconstrained axis.
    /// - Returns: The retained size on a hit, or the configured recipe's result on a miss.
    /// - Precondition: Both proposal axes are finite and nonnegative; this cache is not measuring.
    public func size(of root: Root, toFit size: CGSize) -> CGSize {
        checkAccess()
        let key = key(of: root, toFit: size)
        let measure = measure
        isMeasuring = true
        defer { isMeasuring = false }
        return storage.value(for: key) {
            measure(root, key.context.proposal.fittingSize)
        }
    }

    private static func count(
        of storage: inout MemoizationCache<RequestKey<SizeOperation, DependencySnapshot, SizeContext>, CGSize>
    ) -> Int {
        storage.count
    }

    private func checkAccess() {
        precondition(!isMeasuring, "SizeCache cannot be reentered while its measurement recipe is running.")
    }

    private func key(of root: Root, toFit size: CGSize) -> RequestKey<SizeOperation, DependencySnapshot, SizeContext> {
        precondition(size.width.isFinite && size.width >= 0, "SizeCache proposal width must be finite and nonnegative.")
        precondition(
            size.height.isFinite && size.height >= 0,
            "SizeCache proposal height must be finite and nonnegative."
        )
        let proposal: FittingProposal
        do {
            proposal = try FittingProposal(fitting: size)
        } catch {
            preconditionFailure("SizeCache's validated fitting proposal could not be represented.")
        }
        return RequestKey(
            dependencies: snapshot(of: root),
            context: SizeContext(recipe: ObjectIdentifier(self), proposal: proposal)
        )
    }
}

private enum SizeOperation {}

private struct SizeContext: Hashable {
    let recipe: ObjectIdentifier
    let proposal: FittingProposal
}
