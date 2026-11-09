#if canImport(UIKit)
import UIKit

extension SizeCache where Root: UIView {
    /// Creates a cache for a view that measures with its own `sizeThatFits(_:)` on a miss.
    ///
    /// Use this initializer for leaf views; parents declare children and supply a custom recipe.
    /// Select every property that affects fitting, and keep unselected settings fixed across all
    /// views sharing the cache; see <doc:CacheContract>. Views with equal selected values share
    /// results, and the cache keys both proposal axes without rounding.
    ///
    /// This initializer is exempt from the debug check for undeclared children because the
    /// view's own fitting is opaque to the cache.
    ///
    /// - Parameters:
    ///   - paths: Stable hashable fitting inputs read from the view before lookup.
    ///   - capacity: The maximum number of retained sizes; zero disables storage.
    /// - Important: Do not call this cache from inside the measured view's own `sizeThatFits(_:)`
    ///   override, directly or through a binding. A miss would call the override again and
    ///   reenter the cache. Use a custom recipe that measures children or calls a separate
    ///   uncached routine.
    /// - Precondition: `capacity` is nonnegative.
    public convenience init<each Value>(
        dependingOn paths: repeat KeyPath<Root, each Value>,
        capacity: Int
    ) where repeat each Value: Hashable {
        // The view's own fitting is opaque, so caches it consults internally are not this recipe's children.
        self.init(dependingOn: repeat each paths, capacity: capacity, allowsUndeclaredMeasurements: true) {
            view,
            proposal in
            view.sizeThatFits(proposal)
        }
    }
}
#endif
