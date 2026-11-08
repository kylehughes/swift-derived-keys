import DerivedKeysUI
import UIKit

// expected-error: call to main actor-isolated instance method 'value(for:)' in a synchronous nonisolated context
func invalidUIKitMainActorResultCacheAccess(_ cache: MainActorResultCache<UILabel, CGSize>, label: UILabel) {
    _ = cache.value(for: label)
}
