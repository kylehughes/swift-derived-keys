import CoreGraphics
import DerivedKeys

/// A main-actor handle for measuring a nested root through its original size cache.
///
/// Bindings share the original cache's entries, capacity, recipe, and LRU order. They retain
/// that cache for measurement, but inherited dependency descriptions retain only immutable
/// snapshot capture. Mapping adds no snapshot structure or dependency depth. Roots are read
/// on demand and are not implicitly retained.
@MainActor
public final class SizeCacheBinding<Root>: SizeDependencies<Root> {
    private let lookup: @MainActor (Root, CGSize) -> CGSize

    fileprivate init(
        depth: Int,
        capture: @escaping (Root) -> DependencySnapshot,
        lookup: @escaping @MainActor (Root, CGSize) -> CGSize
    ) {
        self.lookup = lookup
        super.init(depth: depth, capture: capture)
    }

    /// Maps this binding onto another root while sharing the original cache.
    ///
    /// The returned handle retains the original cache. Capturing its dependency description
    /// in a parent retains only dependency readers; the parent's recipe must capture the
    /// handle separately to measure through it.
    /// - Parameter path: The nonoptional nested root to read from each new parent.
    /// - Returns: A handle that follows both paths and measures through the original cache.
    public func bound<Parent>(to path: KeyPath<Parent, Root>) -> SizeCacheBinding<Parent> {
        let capture = capture
        let lookup = lookup
        return SizeCacheBinding<Parent>(
            depth: depth,
            capture: { root in capture(root[keyPath: path]) },
            lookup: { root, proposal in lookup(root[keyPath: path], proposal) }
        )
    }

    /// Returns a shared cached size or synchronously measures the mapped root on a miss.
    ///
    /// Proposal normalization, exact keying, recency, and eviction follow the original cache.
    /// - Parameters:
    ///   - root: The parent whose bound path supplies the root to snapshot and measure.
    ///   - size: The fitting proposal in points passed to the original cache.
    /// - Returns: The retained size on a hit, or the original recipe's result on a miss.
    /// - Precondition: Both proposal axes are finite and nonnegative; the original cache
    ///   is not measuring, including through another binding.
    public func size(of root: Root, toFit size: CGSize) -> CGSize {
        lookup(root, size)
    }
}

extension SizeCache {
    /// Binds this cache to a nested root while sharing its entries and measurement recipe.
    ///
    /// The binding retains this cache. Its inherited snapshot and descriptor operations
    /// retain only immutable capture; they do not measure or change cache recency.
    /// Binding preserves dependency depth and snapshot structure.
    /// - Parameter path: The nonoptional nested root to read from each parent for both
    ///   dependency capture and measurement.
    /// - Returns: A handle that accepts the parent root and shares this cache.
    public func bound<Parent>(to path: KeyPath<Parent, Root>) -> SizeCacheBinding<Parent> {
        let capture = capture
        return SizeCacheBinding<Parent>(
            depth: depth,
            capture: { root in capture(root[keyPath: path]) },
            lookup: { root, proposal in self.size(of: root[keyPath: path], toFit: proposal) }
        )
    }
}
