import CoreGraphics
import DerivedKeys
import DerivedKeysUIKit

/// A synchronous main-actor LRU cache with one configured size-measurement recipe.
///
/// Equal captured dependencies and effective proposals reuse results across root instances.
/// Capture every value read by the recipe, including environment values. Measurement must
/// read values consistent with the preceding snapshot; main-actor isolation does not freeze
/// aliases. Child descriptions contribute values, not child measurements or proposals.
///
/// Entries retain snapshots and sizes without implicitly retaining roots. The configured closure is
/// retained for this cache's lifetime and may explicitly retain caller-owned objects. Sharing
/// this reference shares result storage and recency. Results are stored without validation,
/// rounding, or clamping. Same-cache measurement reentry, including storage inspection or
/// removal through an alias, is unsupported and fails a precondition.
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
