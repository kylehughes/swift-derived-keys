import DerivedKeysUI
import UIKit

@MainActor
func validUIKitMainActorResultCacheAccess() {
    typealias Request = (view: UILabel, width: CGFloat)
    let cache = MainActorResultCache<Request, CGSize>(
        dependingOn: \.view.text,
        \.view.font,
        \.view.numberOfLines,
        \.view.traitCollection.preferredContentSizeCategory,
        \.width,
        capacity: 8
    ) { request in
        request.view.sizeThatFits(CGSize(width: request.width, height: .greatestFiniteMagnitude))
    }
    let label = UILabel()
    _ = cache.value(for: (label, 120))
    cache.removeValue(for: (label, 120))
    cache.removeAll()
    _ = cache.count
    _ = cache.capacity
}
