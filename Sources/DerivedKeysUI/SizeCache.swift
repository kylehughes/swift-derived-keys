import CoreGraphics
import DerivedKeys

/// A main-actor cache that reuses measured sizes for equivalent roots and fitting proposals.
///
/// Roots with equal selected values and the same effective proposal share a cached size. Select
/// every variable value the recipe reads; settings you leave out must stay fixed and match across
/// roots sharing the cache. <doc:CacheContract> states these rules, along with retention,
/// reentrancy, and clearing.
///
/// Child descriptions contribute their selected values to the parent's key, not their measured
/// sizes. Sharing a reference shares storage and recency. Sizes are stored exactly as the recipe
/// returns them, without validation, rounding, or clamping.
@MainActor
public final class SizeCache<Root>: SizeDependencies<Root> {
    /// The maximum number of retained results.
    ///
    /// Zero disables storage.
    public let capacity: Int

    private var isMeasuring = false
    private let measure: @MainActor (Root, CGSize) -> CGSize
    private var storage: MemoizationCache<SizeKey, CGSize>
    #if DEBUG
    private let allowsUndeclaredMeasurements: Bool
    #endif

    override var declarations: SizeDeclarations {
        #if DEBUG
        childDeclarations.union(ownDeclaration)
        #else
        .none
        #endif
    }

    var ownDeclaration: SizeDeclarations {
        #if DEBUG
        .cache(ObjectIdentifier(self))
        #else
        .none
        #endif
    }

    /// The number of retained results.
    ///
    /// - Precondition: This cache is not measuring.
    public var count: Int {
        checkAccess()
        return Self.count(of: &storage)
    }

    /// Creates a cache that measures roots with a recipe you supply.
    ///
    /// Both `paths` and `children` may be empty, and local values precede children in the
    /// snapshot. The recipe must capture the child caches or bindings it measures, because
    /// `children:` retains only their dependency readers. In debug builds, measuring through a
    /// size cache that is not declared in `children:` fails an assertion; see
    /// <doc:CacheContract> for the check.
    ///
    /// - Parameters:
    ///   - paths: Stable hashable values read from each root before lookup.
    ///   - children: Ordered dependency descriptions that contribute to every snapshot,
    ///     whether or not the recipe measures them.
    ///   - capacity: The maximum number of retained sizes; zero disables storage.
    ///   - allowsUndeclaredMeasurements: Pass `true` when the recipe measures through a cache
    ///     that is not in `children:`, such as a fixed captured root that no key path from the
    ///     parent root reaches. You then own the completeness of the selection.
    ///   - measure: The recipe, called on a miss with the root and the normalized proposal.
    ///     It must not call this cache again, directly or through a view's `sizeThatFits(_:)`.
    /// - Precondition: `capacity` is nonnegative, and the composed depth is at most
    ///   ``SizeDependencies/maximumDepth``.
    public init<each Value>(
        dependingOn paths: repeat KeyPath<Root, each Value>,
        children: SizeDependencies<Root>...,
        capacity: Int,
        allowsUndeclaredMeasurements: Bool = false,
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
        #if DEBUG
        self.allowsUndeclaredMeasurements = allowsUndeclaredMeasurements
        #endif
        super
            .init(depth: depth, declarations: Self.declarations(of: children)) { root in
                do {
                    return try DependencySnapshot(children: captures.map { $0(root) })
                } catch {
                    preconditionFailure("SizeCache's checked immutable dependency description exceeded maximumDepth.")
                }
            }
    }

    /// Removes this cache's results, leaving child caches untouched.
    ///
    /// - Precondition: This cache is not measuring.
    public func removeAll() {
        checkAccess()
        storage.removeAll()
    }

    /// Removes the result for the root's current selected values and the proposal.
    ///
    /// A root that has changed since the earlier measurement identifies a different entry.
    /// Child result storage is not accessed.
    /// - Parameters:
    ///   - root: The root whose current selected values identify the entry.
    ///   - size: The fitting proposal of the entry, normalized as during lookup.
    /// - Precondition: Both proposal axes are nonnegative and not NaN; this cache is not measuring.
    public func removeSize(of root: Root, toFit size: CGSize) {
        checkAccess()
        storage.removeValue(for: key(of: root, toFit: size))
    }

    /// Returns the cached size for the root and proposal, measuring on a miss.
    ///
    /// Both proposal axes are part of the key. `CGFloat.greatestFiniteMagnitude` and positive
    /// infinity mean an unconstrained axis, and the recipe receives `greatestFiniteMagnitude`
    /// for either. Signed zero is normalized, and the recipe receives the normalized proposal.
    /// See <doc:CacheContract> for proposals in full.
    ///
    /// Hits promote recency, and a miss at capacity evicts the least recently used result.
    /// At zero capacity every request measures. A parent hit never looks up child results.
    /// - Parameters:
    ///   - root: The current root to read and, on a miss, measure. It is not part of the key
    ///     and the cache does not retain it.
    ///   - size: The fitting proposal in points.
    /// - Returns: The retained size on a hit, or the recipe's result on a miss.
    /// - Precondition: Both proposal axes are nonnegative and not NaN, and this cache is not
    ///   measuring. In debug builds, a lookup from inside another size cache's recipe also
    ///   requires this cache to be declared in that parent's `children:`, unless the parent
    ///   allows undeclared measurements.
    /// - Complexity: Expected amortized constant-time bookkeeping, excluding snapshot
    ///   evaluation, hashing, equality, and measurement.
    public func size(of root: Root, toFit size: CGSize) -> CGSize {
        checkAccess()
        #if DEBUG
        DeclaredChildren.check(ObjectIdentifier(self))
        #endif
        let key = key(of: root, toFit: size)
        let measure = measure
        isMeasuring = true
        defer { isMeasuring = false }
        return storage.value(for: key) {
            #if DEBUG
            DeclaredChildren.push(
                childDeclarations,
                root: ObjectIdentifier(Root.self),
                allowsUndeclared: allowsUndeclaredMeasurements
            )
            defer { DeclaredChildren.pop() }
            #endif
            return measure(root, key.proposal.fittingSize)
        }
    }

    private static func declarations(of children: [SizeDependencies<Root>]) -> SizeDeclarations {
        #if DEBUG
        children.reduce(.none) { $0.union($1.declarations) }
        #else
        .none
        #endif
    }

    private static func count(
        of storage: inout MemoizationCache<SizeKey, CGSize>
    ) -> Int {
        storage.count
    }

    private func checkAccess() {
        precondition(!isMeasuring, "SizeCache cannot be reentered while its measurement recipe is running.")
    }

    private func key(of root: Root, toFit size: CGSize) -> SizeKey {
        precondition(size.width >= 0, "SizeCache proposal width must be nonnegative and not NaN.")
        precondition(size.height >= 0, "SizeCache proposal height must be nonnegative and not NaN.")
        let proposal: FittingProposal
        do {
            proposal = try FittingProposal(fitting: size)
        } catch {
            preconditionFailure("SizeCache's validated fitting proposal could not be represented.")
        }
        return SizeKey(snapshot: snapshot(of: root), proposal: proposal)
    }
}

private struct SizeKey: Hashable {
    let snapshot: DependencySnapshot
    let proposal: FittingProposal
}
