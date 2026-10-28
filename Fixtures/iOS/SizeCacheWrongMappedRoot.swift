import DerivedKeysUI
import UIKit

@MainActor
final class WrongMappedRoot {
    let button = UIButton(type: .system)
}

@MainActor
func invalidMappedRoot() {
    let cache = SizeCache<UILabel>(dependingOn: \.text, capacity: 1) { _, size in size }
    // expected-error: cannot convert value of type
    let _: SizeDependencies<WrongMappedRoot> = cache.at(\WrongMappedRoot.button)
}
