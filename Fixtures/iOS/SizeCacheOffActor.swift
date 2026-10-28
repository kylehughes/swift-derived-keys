import DerivedKeysUI
import UIKit

// expected-error: call to main actor-isolated instance method 'size(of:toFit:)' in a synchronous nonisolated context
func invalidUIKitSizeAccess(_ cache: SizeCache<UILabel>, label: UILabel) {
    _ = cache.size(of: label, toFit: .zero)
}
