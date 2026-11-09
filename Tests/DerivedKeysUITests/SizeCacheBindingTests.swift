import CoreGraphics
import DerivedKeysUI
import Testing

@MainActor
struct SizeCacheBindingTests {
    @Test func bindingsShareDirectEntriesRecencyEvictionAndClearing() {
        var calls = 0
        let cache = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 2) { root, _ in
            calls += 1
            return CGSize(width: root.value, height: 1)
        }
        let first = cache.bound(to: \SizeTestPanel.first)
        let second = cache.bound(to: \SizeTestPanel.second)
        let root = SizeTestPanel()
        #expect(first.size(of: root, toFit: .zero).width == 1)
        #expect(cache.size(of: root.first, toFit: .zero).width == 1)
        #expect(second.size(of: root, toFit: .zero).width == 2)
        _ = first.size(of: root, toFit: .zero)
        root.second.value = 3
        _ = second.size(of: root, toFit: .zero)
        #expect(calls == 3)
        #expect(cache.count == 2)
        _ = cache.size(of: SizeTestItem(2), toFit: .zero)
        #expect(calls == 4)
        cache.removeAll()
        _ = first.size(of: root, toFit: .zero)
        #expect(calls == 5)
        cache.removeSize(of: root.first, toFit: .zero)
        _ = first.size(of: root, toFit: .zero)
        #expect(calls == 6)
    }

    @Test func parentHitsCaptureEachOccurrenceWithoutLookingUpOrPromotingChildren() {
        var calls = 0
        let cache = SizeCache<SizeTestItem>(dependingOn: \.computed, capacity: 2) { root, _ in
            calls += 1
            return CGSize(width: root.value, height: 1)
        }
        let binding = cache.bound(to: \SizeTestPanel.first)
        let parent = SizeCache<SizeTestPanel>(children: binding, binding, capacity: 2) { root, size in
            binding.size(of: root, toFit: size)
        }
        let root = SizeTestPanel()
        _ = parent.size(of: root, toFit: .zero)
        #expect(root.first.reads == 3)
        _ = cache.size(of: SizeTestItem(2), toFit: .zero)
        _ = parent.size(of: root, toFit: .zero)
        #expect(root.first.reads == 5)
        _ = cache.size(of: SizeTestItem(3), toFit: .zero)
        _ = cache.size(of: SizeTestItem(2), toFit: .zero)
        #expect(calls == 3)
        _ = binding.size(of: root, toFit: .zero)
        #expect(calls == 4)
        root.first.value = 4
        #expect(parent.size(of: root, toFit: .zero).width == 4)
        #expect(calls == 5)
    }

    @Test func chainedAndIdentityBindingsPreserveSnapshotsAndMaximumDepth() {
        var cache = SizeCache<SizeTestItem>(capacity: 0) { _, size in size }
        for _ in 1 ..< SizeDependencies<SizeTestItem>.maximumDepth {
            cache = SizeCache<SizeTestItem>(children: cache, capacity: 0) { _, size in size }
        }
        let root = Envelope()
        let direct = cache.bound(to: \SizeTestItem.self)
        let nested = cache.bound(to: \SizeTestPanel.first).bound(to: \Envelope.panel)
        #expect(direct.snapshot(of: root.panel.first) == cache.snapshot(of: root.panel.first))
        #expect(
            nested.snapshot(of: root)
                == cache.bound(to: \SizeTestPanel.first).bound(to: \Envelope.panel).snapshot(of: root)
        )
        #expect(nested.size(of: root, toFit: .zero) == .zero)
    }

    @Test func bindingRetainsCacheAndRecipeUntilReleaseWithoutRetainingRoots() {
        var token: SizeTestItem? = SizeTestItem(7)
        weak let weakToken = token
        var cache: SizeCache<SizeTestItem>? = SizeCache(dependingOn: \.value, capacity: 2) { [token] _, _ in
            CGSize(width: token?.value ?? 0, height: 1)
        }
        weak let weakCache = cache
        var binding: SizeCacheBinding<Envelope>? = cache!.bound(to: \SizeTestPanel.first)
            .bound(to: \Envelope.panel)
        cache = nil
        token = nil
        #expect(weakCache != nil)
        #expect(weakToken != nil)
        weak var weakRoot: Envelope?
        do {
            let root = Envelope()
            weakRoot = root
            #expect(binding?.size(of: root, toFit: .zero).width == 7)
        }
        #expect(weakRoot == nil)
        binding = nil
        #expect(weakCache == nil)
        #expect(weakToken == nil)
    }

    @Test(arguments: ["direct", "chained"])
    func parentsRetainOnlyDependencyReadersOfBindingsInChildren(mapping: String) {
        var token: SizeTestItem? = SizeTestItem(7)
        weak let weakToken = token
        var cache: SizeCache<SizeTestItem>? = SizeCache(dependingOn: \.value, capacity: 1) { [token] _, _ in
            CGSize(width: token?.value ?? 0, height: 1)
        }
        weak let weakCache = cache
        var binding: SizeCacheBinding<SizeTestPanel>? = cache!.bound(to: \SizeTestPanel.first)
        weak let weakBinding = binding
        var chained: SizeCacheBinding<Envelope>? = binding!.bound(to: \Envelope.panel)
        weak let weakChained = chained
        let parent: SizeCache<Envelope>
        do {
            let description: SizeDependencies<Envelope>
            switch mapping {
            case "direct": description = cache!.bound(to: \Envelope.panel.first)
            default: description = chained!
            }
            parent = SizeCache<Envelope>(children: description, capacity: 1) { _, size in size }
        }
        cache = nil
        binding = nil
        chained = nil
        token = nil
        #expect(weakBinding == nil)
        #expect(weakChained == nil)
        #expect(weakCache == nil)
        #expect(weakToken == nil)
        #expect(parent.size(of: Envelope(), toFit: .zero) == .zero)
    }
}

extension SizeCacheBindingTests {
    @MainActor
    private final class Envelope {
        let panel = SizeTestPanel()
    }
}
