import DerivedKeysUI
import UIKit

// expected-error: call to main actor-isolated instance method 'size(of:toFit:)' in a synchronous nonisolated context
func invalidUIKitBindingAccess(_ binding: SizeCacheBinding<UILabel>, label: UILabel) {
    _ = binding.size(of: label, toFit: .zero)
}
