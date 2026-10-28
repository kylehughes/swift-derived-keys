import CoreGraphics
import DerivedKeysUI

// expected-error: call to main actor-isolated instance method 'size(of:toFit:)' in a synchronous nonisolated context
func invalidSizeAccess(_ cache: SizeCache<Int>) {
    _ = cache.size(of: 1, toFit: .zero)
}
