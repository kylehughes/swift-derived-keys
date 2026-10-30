import DerivedKeysUI
import UIKit

@MainActor
final class UIKitWrongBindingRoot {
    let button = UIButton(type: .system)
}

@MainActor
func invalidUIKitBindingRoot() {
    let cache = SizeCache<UILabel>(dependingOn: \.text, capacity: 1)
    // expected-error: cannot convert value of type
    let _: SizeCacheBinding<UIKitWrongBindingRoot> = cache.bound(to: \UIKitWrongBindingRoot.button)
}
