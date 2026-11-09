import CoreGraphics
import DerivedKeys

/// A binding that reads and measures a nested root through its original ``SizeCache``.
///
/// Created with ``SizeCache/bound(to:)``, a binding reads the nested root from a parent root by
/// key path for both dependency capture and measurement. It retains the original cache, shares
/// its entries, capacity, and recency, and adds no storage or snapshot depth.
///
/// Listing a binding in a parent's `children:` retains only its dependency readers; the parent's
/// recipe must also capture the binding to measure through it. See <doc:CacheContract> for
/// child-declaration and retention rules.
@MainActor
public final class SizeCacheBinding<Root>: SizeDependencies<Root> {
    private let lookup: @MainActor (Root, CGSize) -> CGSize
    private let target: SizeDeclarations

    fileprivate init(
        depth: Int,
        target: SizeDeclarations,
        declarations: SizeDeclarations,
        capture: @escaping (Root) -> DependencySnapshot,
        lookup: @escaping @MainActor (Root, CGSize) -> CGSize
    ) {
        self.lookup = lookup
        self.target = target
        super.init(depth: depth, declarations: declarations, capture: capture)
    }

    /// Maps this binding onto a parent of its root.
    ///
    /// The returned binding follows both paths and shares the original cache.
    /// - Parameter path: The nonoptional nested root to read from each new parent.
    /// - Returns: A binding that accepts the new parent root.
    public func bound<Parent>(to path: KeyPath<Parent, Root>) -> SizeCacheBinding<Parent> {
        let capture = capture
        let lookup = lookup
        return SizeCacheBinding<Parent>(
            depth: depth,
            target: rebasedDeclarations(of: target, onto: path),
            declarations: rebasedDeclarations(of: declarations, onto: path),
            capture: { root in capture(root[keyPath: path]) },
            lookup: { root, proposal in lookup(root[keyPath: path], proposal) }
        )
    }

    /// Returns the cached size for the bound root and proposal, measuring on a miss.
    ///
    /// Proposal handling, recency, and eviction follow the original cache; see
    /// <doc:CacheContract>.
    /// - Parameters:
    ///   - root: The parent whose bound path supplies the root to read and measure.
    ///   - size: The fitting proposal in points, passed to the original cache.
    /// - Returns: The retained size on a hit, or the original recipe's result on a miss.
    /// - Precondition: Both proposal axes are nonnegative and not NaN, and the original cache is
    ///   not measuring, including through another binding. In debug builds, a lookup from inside
    ///   another size cache's recipe also requires the original cache—and this binding's path
    ///   when `Root` is that parent's root—to be declared in the parent's `children:`, unless
    ///   the parent allows undeclared measurements.
    public func size(of root: Root, toFit size: CGSize) -> CGSize {
        #if DEBUG
        DeclaredChildren.noteBinding(target)
        #endif
        return lookup(root, size)
    }
}

extension SizeCache {
    /// Binds this cache to a nested root of a parent.
    ///
    /// Pass the binding in a parent's `children:` and capture it in the parent's recipe. The
    /// binding retains this cache, shares its entries and recency, and leaves dependency depth
    /// and snapshot structure unchanged; see <doc:CacheContract>.
    /// - Parameter path: The nonoptional nested root to read from each parent, for both
    ///   dependency capture and measurement.
    /// - Returns: A binding that accepts the parent root.
    public func bound<Parent>(to path: KeyPath<Parent, Root>) -> SizeCacheBinding<Parent> {
        let capture = capture
        return SizeCacheBinding<Parent>(
            depth: depth,
            target: rebasedDeclarations(of: ownDeclaration, onto: path),
            declarations: rebasedDeclarations(of: declarations, onto: path),
            capture: { root in capture(root[keyPath: path]) },
            lookup: { root, proposal in self.size(of: root[keyPath: path], toFit: proposal) }
        )
    }
}
