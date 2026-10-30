import DerivedKeysUI
import UIKit

@MainActor
func invalidUIKitBindingInitializer() {
    // expected-error: initializer is inaccessible due to 'fileprivate' protection level
    _ = SizeCacheBinding<UILabel>(depth: 1, capture: { _ in fatalError("Must not compile") }, lookup: { _, size in size })
}
