import CoreGraphics
import DerivedKeysUI

final class SizeRoot {
    var title = "Text"
    var count = 1
    var child = SizeChild()
}

final class SizeChild {
    var value = 2
}

@MainActor
func validSizeAccess() {
    let child = SizeCache<SizeChild>(dependingOn: \.value, capacity: 2) { _, proposal in proposal }
    let same = SizeCache<SizeRoot>(dependingOn: \.title, \.count, capacity: 2) { _, proposal in proposal }
    let cache = SizeCache<SizeRoot>(children: same, child.at(\.child), capacity: 2) { root, proposal in
        child.size(of: root.child, toFit: proposal)
    }
    let empty = SizeCache<SizeRoot>(capacity: 0) { _, proposal in proposal }
    let root = SizeRoot()
    _ = cache.snapshot(of: root)
    _ = cache.size(of: root, toFit: CGSize(width: 100, height: 20))
    cache.removeSize(of: root, toFit: .zero)
    cache.removeAll()
    _ = cache.count
    _ = empty.capacity
}
