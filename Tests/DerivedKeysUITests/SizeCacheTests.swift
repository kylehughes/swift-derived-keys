import CoreGraphics
import DerivedKeys
import DerivedKeysUI
import Testing

@MainActor
struct SizeCacheTests {
    @Test func heterogeneousNestedPathsZeroDependenciesAndCrossInstanceReuse() {
        var calls = 0
        let cache = SizeCache<SizeTestPanel>(dependingOn: \.first.text, \.spacing, \.enabled, capacity: 4) {
            root,
            proposal in
            calls += 1
            return CGSize(width: proposal.width, height: CGFloat(root.first.text.count + root.spacing))
        }
        let first = SizeTestPanel()
        let second = SizeTestPanel()
        #expect(cache.size(of: first, toFit: bounds) == cache.size(of: second, toFit: bounds))
        #expect(calls == 1)
        second.enabled = false
        _ = cache.size(of: second, toFit: bounds)
        #expect(calls == 2)
        let empty = SizeCache<SizeTestPanel>(capacity: 2) { _, proposal in proposal }
        #expect(empty.size(of: first, toFit: bounds) == bounds)
        #expect(empty.size(of: second, toFit: bounds) == bounds)
        #expect(empty.count == 1)
        #expect(empty.snapshot(of: first) == empty.snapshot(of: second))
    }

    @Test func proposalAxesAreExactAndSignedZerosAreNormalized() {
        var received: [CGSize] = []
        let cache = SizeCache<SizeTestPanel>(capacity: 8) { _, proposal in
            received.append(proposal)
            return proposal
        }
        let root = SizeTestPanel()
        for size in [CGSize(width: 1, height: 2), CGSize(width: 2, height: 2), CGSize(width: 2, height: 3)] {
            #expect(cache.size(of: root, toFit: size) == size)
        }
        _ = cache.size(of: root, toFit: CGSize(width: -CGFloat.zero, height: -CGFloat.zero))
        _ = cache.size(of: root, toFit: .zero)
        #expect(received.count == 4)
        #expect(received[3].width.native.bitPattern == CGFloat.zero.native.bitPattern)
        #expect(received[3].height.native.bitPattern == CGFloat.zero.native.bitPattern)
        let maximum = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        #expect(cache.size(of: root, toFit: maximum) == maximum)
        let precise = CGSize(width: CGFloat(1).nextUp, height: 2)
        _ = cache.size(of: root, toFit: precise)
        #expect(received.count == 6)
    }

    @Test func snapshotsPreserveValuesTypesOrderAndComputedProjections() {
        let cache = SizeCache<SizeTestItem>(dependingOn: \.computed, \.collision, capacity: 4) { root, _ in
            CGSize(width: root.value, height: 1)
        }
        let first = SizeTestItem(1)
        let original = cache.snapshot(of: first)
        #expect(original == cache.snapshot(of: SizeTestItem(1)))
        first.value = 2
        #expect(original != cache.snapshot(of: first))
        #expect(cache.size(of: SizeTestItem(1), toFit: bounds).width == 1)
        #expect(cache.size(of: SizeTestItem(2), toFit: bounds).width == 2)
        let collisions = SizeCache<SizeTestItem>(dependingOn: \.collision, capacity: 4) { root, _ in
            CGSize(width: root.value, height: 1)
        }
        #expect(collisions.size(of: SizeTestItem(1), toFit: bounds).width == 1)
        #expect(collisions.size(of: SizeTestItem(2), toFit: bounds).width == 2)
        #expect(collisions.count == 2)
        let ints = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 1) { _, size in size }
        let doubles = SizeCache<SizeTestItem>(dependingOn: \.double, capacity: 1) { _, size in size }
        #expect(ints.snapshot(of: SizeTestItem(1)) != doubles.snapshot(of: SizeTestItem(1)))
        let forward = SizeCache<SizeTestPanel>(dependingOn: \.spacing, \.first.value, capacity: 1) { _, size in size }
        let reverse = SizeCache<SizeTestPanel>(dependingOn: \.first.value, \.spacing, capacity: 1) { _, size in size }
        #expect(forward.snapshot(of: SizeTestPanel()) != reverse.snapshot(of: SizeTestPanel()))
    }

    @Test func childAndParentDependenciesInvalidateIndependently() {
        var parentCalls = 0
        var childCalls = 0
        let child = SizeCache<SizeTestItem>(dependingOn: \.text, capacity: 4) { root, size in
            childCalls += 1
            return CGSize(width: size.width, height: CGFloat(root.text.count))
        }
        let parent = SizeCache<SizeTestPanel>(dependingOn: \.spacing, children: child.at(\.first), capacity: 4) {
            root,
            size in
            parentCalls += 1
            let inner = child.size(
                of: root.first,
                toFit: CGSize(width: size.width - CGFloat(root.spacing * 2), height: size.height)
            )
            return CGSize(width: inner.width + CGFloat(root.spacing * 2), height: inner.height + CGFloat(root.spacing))
        }
        let root = SizeTestPanel()
        #expect(parent.size(of: root, toFit: bounds) == CGSize(width: 100, height: 7))
        #expect(parent.size(of: root, toFit: bounds).width == 100)
        #expect(parentCalls == 1)
        #expect(childCalls == 1)
        root.spacing = 5
        #expect(parent.size(of: root, toFit: bounds).height == 8)
        #expect(parentCalls == 2)
        #expect(childCalls == 2)
        root.first.text = "longer"
        #expect(parent.size(of: root, toFit: bounds).height == 11)
        #expect(parentCalls == 3)
        #expect(childCalls == 3)
        #expect(child.size(of: root.first, toFit: CGSize(width: 90, height: 80)).width == 90)
        #expect(childCalls == 3)
    }

    @Test func parentSpacingChildInputsAndInnerProposalsInvalidateAtTheirOwnBoundaries() {
        var textCalls = 0
        var buttonCalls = 0
        var parentCalls = 0
        var textProposals: [CGSize] = []
        var buttonProposals: [CGSize] = []
        let text = SizeCache<SizeTestPanel>(dependingOn: \.first.text, capacity: 8) { root, proposal in
            textCalls += 1
            textProposals.append(proposal)
            return CGSize(width: proposal.width, height: CGFloat(root.first.text.count))
        }
        let button = SizeCache<SizeTestPanel>(dependingOn: \.enabled, capacity: 8) { root, proposal in
            buttonCalls += 1
            buttonProposals.append(proposal)
            return CGSize(width: proposal.width, height: root.enabled ? 10 : 5)
        }
        let parent = SizeCache<SizeTestPanel>(
            dependingOn: \.spacing,
            \.padding,
            children: text,
            button,
            capacity: 8
        ) { root, proposal in
            parentCalls += 1
            let innerProposal = CGSize(
                width: proposal.width - CGFloat(root.padding * 2),
                height: proposal.height
            )
            let textSize = text.size(of: root, toFit: innerProposal)
            let buttonSize = button.size(of: root, toFit: innerProposal)
            return CGSize(
                width: max(textSize.width, buttonSize.width) + CGFloat(root.padding * 2),
                height: textSize.height + buttonSize.height + CGFloat(root.spacing)
            )
        }
        let root = SizeTestPanel()
        #expect(parent.size(of: root, toFit: bounds) == CGSize(width: 100, height: 17))
        #expect([parentCalls, textCalls, buttonCalls] == [1, 1, 1])
        root.spacing = 7
        #expect(parent.size(of: root, toFit: bounds) == CGSize(width: 100, height: 20))
        #expect([parentCalls, textCalls, buttonCalls] == [2, 1, 1])
        root.first.text = "longer"
        #expect(parent.size(of: root, toFit: bounds) == CGSize(width: 100, height: 23))
        #expect([parentCalls, textCalls, buttonCalls] == [3, 2, 1])
        let wider = CGSize(width: 120, height: 80)
        #expect(parent.size(of: root, toFit: wider).width == 120)
        #expect([parentCalls, textCalls, buttonCalls] == [4, 3, 2])
        root.padding = 8
        #expect(parent.size(of: root, toFit: wider).width == 120)
        #expect([parentCalls, textCalls, buttonCalls] == [5, 4, 3])
        #expect(
            textProposals == [
                CGSize(width: 92, height: 80), CGSize(width: 92, height: 80),
                CGSize(width: 112, height: 80), CGSize(width: 104, height: 80),
            ]
        )
        #expect(
            buttonProposals == [
                CGSize(width: 92, height: 80), CGSize(width: 112, height: 80), CGSize(width: 104, height: 80),
            ]
        )
        root.first.reads += 1
        #expect(parent.size(of: root, toFit: wider).height == 23)
        #expect([parentCalls, textCalls, buttonCalls] == [5, 4, 3])
    }

    @Test func sharedLeafCacheMeasuresDistinctBindingsAndReusesUnchangedSibling() {
        var leafCalls = 0
        var parentCalls = 0
        let leaf = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 4) { root, _ in
            leafCalls += 1
            return CGSize(width: root.value, height: 1)
        }
        let parent = SizeCache<SizeTestPanel>(
            children: leaf.at(\.first),
            leaf.at(\.second),
            capacity: 4
        ) { root, proposal in
            parentCalls += 1
            let first = leaf.size(of: root.first, toFit: proposal)
            let second = leaf.size(of: root.second, toFit: proposal)
            return CGSize(width: first.width + second.width, height: max(first.height, second.height))
        }
        let root = SizeTestPanel()
        #expect(parent.size(of: root, toFit: bounds).width == 3)
        #expect(leafCalls == 2)
        #expect(parentCalls == 1)
        root.second.value = 4
        #expect(parent.size(of: root, toFit: bounds).width == 5)
        #expect(leafCalls == 3)
        #expect(parentCalls == 2)
        #expect(leaf.size(of: root.first, toFit: bounds).width == 1)
        #expect(leafCalls == 3)
        root.first.reads += 1
        #expect(parent.size(of: root, toFit: bounds).width == 5)
        #expect(leafCalls == 3)
        #expect(parentCalls == 2)
    }

    @Test func parentHitsDoNotPromoteChildResults() {
        var childCalls = 0
        let child = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 2) { root, _ in
            childCalls += 1
            return CGSize(width: root.value, height: 1)
        }
        let parent = SizeCache<SizeTestItem>(children: child, capacity: 2) { root, size in
            child.size(of: root, toFit: size)
        }
        _ = parent.size(of: SizeTestItem(1), toFit: bounds)
        _ = child.size(of: SizeTestItem(2), toFit: bounds)
        _ = parent.size(of: SizeTestItem(1), toFit: bounds)
        _ = child.size(of: SizeTestItem(3), toFit: bounds)
        _ = child.size(of: SizeTestItem(2), toFit: bounds)
        #expect(childCalls == 3)
        _ = child.size(of: SizeTestItem(1), toFit: bounds)
        #expect(childCalls == 4)
    }

    @Test func threeLevelsMixedChildrenAndRepeatedBindingsCaptureEachOccurrence() {
        let leaf = SizeCache<SizeTestItem>(dependingOn: \.computed, capacity: 2) { _, size in size }
        let direct = SizeCache<SizeTestPanel>(dependingOn: \.enabled, capacity: 2) { _, size in size }
        let middle = SizeCache<SizeTestPanel>(
            dependingOn: \.spacing,
            children: direct,
            leaf.at(\.first),
            leaf.at(\.second),
            capacity: 2
        ) { _, size in size }
        let top = SizeCache<SizeTestPanel>(children: middle, capacity: 2) { _, size in size }
        let root = SizeTestPanel()
        let original = top.snapshot(of: root)
        #expect(root.first.reads == 1)
        #expect(root.second.reads == 1)
        root.second.value += 1
        #expect(original != top.snapshot(of: root))
        #expect(root.first.reads == 2)
        #expect(root.second.reads == 2)
        let repeated = SizeCache<SizeTestPanel>(children: leaf.at(\.first), leaf.at(\.first), capacity: 1) { _, size in
            size
        }
        _ = repeated.snapshot(of: root)
        #expect(root.first.reads == 4)
        root.enabled = false
        #expect(original != top.snapshot(of: root))
    }

    @Test func threeLevelsMeasureIndependentlyAndInvalidateThroughNestedValues() {
        var calls = [0, 0, 0]
        let leaf = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 2) { root, _ in
            calls[0] += 1
            return CGSize(width: root.value, height: 1)
        }
        let middle = SizeCache<SizeTestPanel>(children: leaf.at(\.first), capacity: 2) { root, proposal in
            calls[1] += 1
            return leaf.size(of: root.first, toFit: proposal)
        }
        let top = SizeCache<SizeTestPanel>(children: middle, capacity: 2) { root, proposal in
            calls[2] += 1
            return middle.size(of: root, toFit: proposal)
        }
        let root = SizeTestPanel()
        #expect(top.size(of: root, toFit: bounds).width == 1)
        #expect(top.size(of: root, toFit: bounds).width == 1)
        #expect(calls == [1, 1, 1])
        root.first.value = 2
        #expect(top.size(of: root, toFit: bounds).width == 2)
        #expect(calls == [2, 2, 2])
    }

    @Test func childClearingAndEvictionPreserveParentResults() {
        var calls = 0
        let child = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 1) { root, _ in
            CGSize(width: root.value, height: 1)
        }
        let parent = SizeCache<SizeTestItem>(children: child, capacity: 2) { root, proposal in
            calls += 1
            return child.size(of: root, toFit: proposal)
        }
        _ = parent.size(of: SizeTestItem(1), toFit: bounds)
        child.removeAll()
        _ = parent.size(of: SizeTestItem(1), toFit: bounds)
        #expect(child.count == 0)
        _ = child.size(of: SizeTestItem(2), toFit: bounds)
        _ = child.size(of: SizeTestItem(3), toFit: bounds)
        _ = parent.size(of: SizeTestItem(1), toFit: bounds)
        #expect(calls == 1)
        parent.removeAll()
        #expect(child.count == 1)
    }

    @Test func independentRecipesSharedAliasesZeroCapacityAndCurrentKeyRemoval() {
        let first = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 2) { _, _ in CGSize(width: 1, height: 1) }
        let second = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 2) { _, _ in CGSize(width: 2, height: 2) }
        let root = SizeTestItem(1)
        #expect(first.size(of: root, toFit: bounds).width == 1)
        #expect(second.size(of: root, toFit: bounds).width == 2)
        let alias = first
        #expect(alias === first)
        root.value = 2
        alias.removeSize(of: root, toFit: bounds)
        #expect(first.count == 1)
        root.value = 1
        alias.removeSize(of: root, toFit: CGSize(width: 100, height: 81))
        #expect(first.count == 1)
        alias.removeSize(of: root, toFit: bounds)
        #expect(first.count == 0)
        var calls = 0
        let disabled = SizeCache<SizeTestItem>(capacity: 0) { _, size in
            calls += 1
            return size
        }
        _ = disabled.size(of: root, toFit: bounds)
        _ = disabled.size(of: root, toFit: bounds)
        #expect(calls == 2)
        #expect(disabled.count == 0)
        #expect(disabled.capacity == 0)
    }

    @Test func aliasesShareLRURecencyAndBoundedStorage() {
        var calls = 0
        let cache = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 2) { root, _ in
            calls += 1
            return CGSize(width: root.value, height: 1)
        }
        let alias = cache
        _ = cache.size(of: SizeTestItem(1), toFit: bounds)
        _ = cache.size(of: SizeTestItem(2), toFit: bounds)
        _ = alias.size(of: SizeTestItem(1), toFit: bounds)
        _ = alias.size(of: SizeTestItem(3), toFit: bounds)
        _ = cache.size(of: SizeTestItem(1), toFit: bounds)
        #expect(calls == 3)
        _ = cache.size(of: SizeTestItem(2), toFit: bounds)
        #expect(calls == 4)
        #expect(cache.count == 2)
        #expect(cache.capacity == 2)
        alias.removeAll()
        #expect(cache.count == 0)
    }

    @Test func rootsAreReleasedAndDescriptionsDoNotRetainChildCacheOrRecipe() {
        let cache = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 2) { root, _ in
            CGSize(width: root.value, height: 1)
        }
        weak var weakRoot: SizeTestItem?
        do {
            let root = SizeTestItem(1)
            weakRoot = root
            _ = cache.size(of: root, toFit: bounds)
        }
        #expect(weakRoot == nil)
        var token: SizeTestItem? = SizeTestItem(8)
        weak let weakToken = token
        var child: SizeCache<SizeTestItem>? = SizeCache<SizeTestItem>(dependingOn: \.value, capacity: 1) {
            [token] _, _ in
            CGSize(width: token?.value ?? 0, height: 1)
        }
        weak let weakChild = child
        let mapped = child!.at(\SizeTestPanel.first)
        let parent = SizeCache<SizeTestPanel>(children: child!.at(\.first), capacity: 1) { _, size in size }
        child = nil
        token = nil
        #expect(weakChild == nil)
        #expect(weakToken == nil)
        #expect(mapped.snapshot(of: SizeTestPanel()) != parent.snapshot(of: SizeTestPanel()))
        #expect(parent.size(of: SizeTestPanel(), toFit: bounds) == bounds)
    }

    @Test func configuredRecipeRetainsItsExplicitCapturesUntilCacheRelease() {
        var owner: SizeTestItem? = SizeTestItem(7)
        weak let weakOwner = owner
        var cache: SizeCache<SizeTestItem>? = SizeCache(capacity: 1) { [owner] _, _ in
            CGSize(width: owner?.value ?? 0, height: 1)
        }
        owner = nil
        #expect(weakOwner != nil)
        #expect(cache?.size(of: SizeTestItem(), toFit: bounds).width == 7)
        cache = nil
        #expect(weakOwner == nil)
    }

    @Test func maximumDepthCanBeConstructedAndMappingPreservesIt() {
        var description: SizeDependencies<SizeTestItem> = SizeCache<SizeTestItem>(capacity: 0) { _, size in size }
        for _ in 1 ..< SizeDependencies<SizeTestItem>.maximumDepth {
            description = SizeCache<SizeTestItem>(children: description, capacity: 0) { _, size in size }
        }
        #expect(
            description.snapshot(of: SizeTestItem(1))
                == description.at(\SizeTestPanel.first).snapshot(of: SizeTestPanel())
        )
    }

    private var bounds: CGSize { CGSize(width: 100, height: 80) }
}

@MainActor
final class SizeTestItem {
    var value: Int
    var text = "abc"
    var reads = 0
    var double: Double { Double(value) }
    var collision: SizeTestCollision { SizeTestCollision(value: value) }
    var computed: Int {
        reads += 1
        return value
    }
    init(_ value: Int = 1) { self.value = value }
}

@MainActor
final class SizeTestPanel {
    let first = SizeTestItem()
    let second = SizeTestItem(2)
    var spacing = 4
    var padding = 4
    var enabled = true
}

struct SizeTestCollision: Hashable {
    let value: Int
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
}
