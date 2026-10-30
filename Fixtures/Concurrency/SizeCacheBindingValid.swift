import DerivedKeysUI

final class BindingLeaf {
    var value = 1
}

final class BindingRoot {
    let leaf = BindingLeaf()
}

final class BindingEnvelope {
    let root = BindingRoot()
}

@MainActor
func validBindingAccess() {
    let cache = SizeCache<BindingLeaf>(dependingOn: \.value, capacity: 2) { _, size in size }
    let binding: SizeCacheBinding<BindingRoot> = cache.bound(to: \.leaf)
    let chained = binding.bound(to: \BindingEnvelope.root)
    let root = BindingRoot()
    let parent = SizeCache<BindingRoot>(children: binding, binding, binding.at(\.self), capacity: 1) { root, size in
        binding.size(of: root, toFit: size)
    }
    _ = binding.snapshot(of: root)
    _ = binding.size(of: root, toFit: .zero)
    _ = chained.size(of: BindingEnvelope(), toFit: .zero)
    _ = parent.size(of: root, toFit: .zero)
    _ = cache.bound(to: \BindingLeaf.self).size(of: root.leaf, toFit: .zero)
}
