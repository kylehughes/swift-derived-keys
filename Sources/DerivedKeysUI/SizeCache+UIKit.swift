#if canImport(UIKit)
import UIKit

extension SizeCache where Root: UIView {
    /// Creates a cache that measures the supplied view with `sizeThatFits(_:)` on a miss.
    ///
    /// Use this initializer for leaves without child caches. Parents declare children and
    /// supply a custom recipe. Select every variable input affecting fitting. All unselected
    /// measurement settings must be identical across every view sharing this cache and
    /// remain fixed for its lifetime; select settings that vary or use separate caches.
    /// Views with equal captured values share results. Both exact proposal axes enter the
    /// key; signed zero is normalized before fitting. This initializer adds no observation
    /// or rounding.
    ///
    /// - Parameters:
    ///   - paths: Stable hashable fitting inputs read from the view before lookup.
    ///   - capacity: The maximum number of retained sizes; zero disables storage.
    /// - Important: The view's `sizeThatFits(_:)` must not call back into this cache for that
    ///   measurement, including through a binding; same-cache reentry fails a precondition.
    ///   For that integration, a custom recipe must measure children or call a separate
    ///   uncached routine, rather than calling the cached override again.
    /// - Precondition: Capacity is nonnegative and dependency depth is at most `maximumDepth`.
    public convenience init<each Value>(
        dependingOn paths: repeat KeyPath<Root, each Value>,
        capacity: Int
    ) where repeat each Value: Hashable {
        self.init(dependingOn: repeat each paths, capacity: capacity) { view, proposal in
            view.sizeThatFits(proposal)
        }
    }
}
#endif
