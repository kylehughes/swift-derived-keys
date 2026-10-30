#if canImport(UIKit)
import UIKit

extension SizeCache where Root: UIView {
    /// Creates a cache that measures the supplied view with `sizeThatFits(_:)` on a miss.
    ///
    /// Declare every input affecting fitting through the selected paths, or keep it fixed
    /// for the cache's lifetime. Views with equal captured values share results. Both exact
    /// proposal axes enter the key; signed zero is normalized before fitting. This initializer
    /// adds no observation or rounding. Use the custom recipe initializer for child descriptions.
    ///
    /// - Important: The view's `sizeThatFits(_:)` must not call back into this cache for that
    ///   measurement, including through a binding; same-cache reentry fails a precondition.
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
