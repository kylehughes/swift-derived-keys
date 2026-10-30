import CoreGraphics
import DerivedKeys

/// A main-actor view of a size cache through a root key path.
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
    /// The returned binding retains the lookup capability. Its snapshot capture remains
    /// independent of that capability, so parent dependency descriptions do not retain
    /// the lookup capability.
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
    public func bound<Parent>(to path: KeyPath<Parent, Root>) -> SizeCacheBinding<Parent> {
        let capture = capture
        return SizeCacheBinding<Parent>(
            depth: depth,
            capture: { root in capture(root[keyPath: path]) },
            lookup: { root, proposal in self.size(of: root[keyPath: path], toFit: proposal) }
        )
    }
}
