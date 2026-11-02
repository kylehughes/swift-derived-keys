# ``DerivedKeysUI``

Cache measurements by selected key paths, then compose child caches to reuse an entire layout size.

## Overview

Create a ``SizeCache`` once in a retained main-actor owner. For leaf views without child caches, its UIKit convenience initializer selects heterogeneous hashable values by key path and calls the passed view's `sizeThatFits(_:)` on a miss. Parents supply a closure and declare their children. Use a closure for other custom recipes or non-UIKit roots too. Both initializers support zero selected properties.

Select every variable property the calculation reads. Every unselected measurement setting must be identical across all roots sharing the cache and remain fixed for its lifetime. Select settings that vary, or use separate caches. Here the caller keeps each label's remaining settings at the same defaults:

```swift
import DerivedKeysUI
import UIKit

@MainActor
func makeTextSizes() -> SizeCache<UILabel> {
    SizeCache<UILabel>(dependingOn: \.text, \.font, \.numberOfLines, capacity: 256)
}

@MainActor
func measureText(using sizes: SizeCache<UILabel>) -> CGSize {
    let label = UILabel()
    label.text = "Unread messages"
    label.font = .systemFont(ofSize: 17)
    label.numberOfLines = 1
    return sizes.size(
        of: label,
        toFit: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude)
    )
}
```

Retain the result of `makeTextSizes()` in a view or another main-actor owner, and pass it to `measureText(using:)` for successive requests.

A lookup supplies the current root and fitting proposal. The root needs neither Hashable nor Sendable conformance and is not implicitly part of the key. The cache automatically keys both fitting dimensions, normalizes signed zero, and supplies that same normalized proposal to the calculation.

Finite nonnegative values are accepted, including the greatest finite value as an unbounded sentinel. NaN, infinity, and negative proposals fail descriptive preconditions. The cache does not round or clamp measurement results.

## Compose child measurements

Pass child caches in `children:` when creating a parent with the closure initializer. The native UIKit convenience initializer is for leaves and has no child list. A parent hit skips its calculation and every child result lookup. A parent miss runs the configured calculation, where each child lookup can independently hit. Transform proposals in the calculation and declare any values that affect the transformation. Children key the actual proposals they receive. All declared children participate in the dependency snapshot even when a branch will not measure them.

Use `child.bound(to: \Parent.child)` for a child with a different root type. The resulting ``SizeCacheBinding`` is a main-actor dependency description and measurement handle: pass it in `children:` and capture it to call `size(of:toFit:)` with the parent root. Bindings can be chained, and distinct root bindings are traversed independently.

This pair stacks a title and subtitle without spacing. Both labels use the same fixed default measurement settings apart from their selected text, font, and line limit. Retain the returned parent cache; its calculation retains the bound child handles.

```swift
@MainActor
final class PairView: UIView {
    let title = UILabel()
    let subtitle = UILabel()
}

@MainActor
func makePairSizes(titleSizes: SizeCache<UILabel>) -> SizeCache<PairView> {
    let titleSizing = titleSizes.bound(to: \PairView.title)
    let subtitleSizing = titleSizes.bound(to: \PairView.subtitle)
    return SizeCache<PairView>(
        children: titleSizing,
        subtitleSizing,
        capacity: 128
    ) { pair, proposal in
        let titleSize = titleSizing.size(of: pair, toFit: proposal)
        let subtitleSize = subtitleSizing.size(of: pair, toFit: proposal)
        return CGSize(
            width: max(titleSize.width, subtitleSize.width),
            height: titleSize.height + subtitleSize.height
        )
    }
}

@MainActor
func measurePair(using sizes: SizeCache<PairView>) -> CGSize {
    let pair = PairView()
    pair.title.text = "Messages"
    pair.subtitle.text = "Three unread"
    return sizes.size(
        of: pair,
        toFit: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude)
    )
}
```

Create the parent with `makePairSizes(titleSizes: makeTextSizes())`, then pass that retained cache to `measurePair(using:)`. The two bindings share the label cache while capturing each label's own values.

Each lookup uses the original cache; binding adds no storage, key identity, or snapshot depth. Inspect or clear the original cache, since bindings expose no count, capacity, or clearing operations.

Use ``SizeDependencies/at(_:)`` for dependency-only mapping. That descriptor retains dependency readers without retaining the cache, binding, measurement closure, or entries. Parent child-description capture has the same retention rule. A binding itself retains its original cache, so the calculation must capture the handles it calls. The graph is immutable and acyclic by construction; its snapshot depth is checked against ``SizeDependencies/maximumDepth``.

## Ownership and completeness

A view, screen-owned bundle, or intentionally shared static property can own caches. Composition imposes no ownership model. Each reference owns one bounded result cache; sharing the reference shares storage and recency. Clearing a parent clears only that cache, and child clearing or eviction does not invalidate a semantically valid parent result. Clear every affected cache if an undeclared external change invalidates results, or represent that change in selected values.

Snapshots retain full equality-checkable values, concrete types, and child structure. They do not deep-copy mutable references. Project immutable values, including through computed properties, and keep all result-relevant state consistent between selection and computation. The configured closure is retained; user captures and selected reference values can retain objects, but roots passed to lookup are not implicitly retained. The API observes no changes and schedules no UIKit layout.

Each cache uses the generic core's bounded LRU. Zero capacity disables storage. Same-cache measurement reentry, including count inspection or clearing during the recipe, fails a descriptive precondition before accessing storage. Recursive calls to distinct caches are supported.

Do not call a native-fitting cache from the measured view's own `sizeThatFits(_:)` override: a miss invokes the override again. Supply a custom recipe that measures children or calls a separate uncached measurement routine. A custom recipe must also avoid calling the measured view's `sizeThatFits(_:)` when that override uses this cache; changing initializers alone does not prevent recursion. Neither initializer discovers undeclared inputs or makes mutable `Hashable` aliases stable.

## Topics

### Measure and reuse

- ``SizeCache``
- ``SizeCacheBinding``

### Map and inspect dependencies

- ``SizeDependencies``
