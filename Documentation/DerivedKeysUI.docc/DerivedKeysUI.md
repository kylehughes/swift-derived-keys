# ``DerivedKeysUI``

Cache measurements by selected key paths, then compose child caches to reuse an entire layout size.

## Overview

Create a ``SizeCache`` once in a retained main-actor owner. Its UIKit convenience initializer selects heterogeneous hashable values by key path and calls the passed view's `sizeThatFits(_:)` on a miss. Use the closure initializer for custom recipes or non-UIKit roots. Both initializers support zero selected properties.

Select every property the actual calculation reads. This label example assumes its other measurement settings are fixed.

```swift
import DerivedKeysUI
import UIKit

@MainActor
func makeTextSizes() -> SizeCache<UILabel> {
    SizeCache<UILabel>(dependingOn: \.text, \.font, \.numberOfLines, capacity: 256)
}
```

A lookup supplies the current root and fitting proposal. The root needs neither Hashable nor Sendable conformance and is not implicitly part of the key. The cache automatically keys both fitting dimensions, normalizes signed zero, and supplies that same normalized proposal to the calculation.

Finite nonnegative values are accepted, including the greatest finite value as an unbounded sentinel. NaN, infinity, and negative proposals fail descriptive preconditions. The cache does not round or clamp measurement results.

## Compose child measurements

Pass child caches in `children:` when creating a parent. A parent hit skips its calculation and every child result lookup. A parent miss runs the configured calculation, where each child lookup can independently hit. Transform proposals in the calculation and declare any values that affect the transformation. Children key the actual proposals they receive. All declared children participate in the dependency snapshot even when a branch will not measure them.

Use `child.bound(to: \Parent.child)` for a child with a different root type. The resulting ``SizeCacheBinding`` is a main-actor dependency description and measurement handle: pass it in `children:` and capture it to call `size(of:toFit:)` with the parent root. Bindings can be chained, and distinct root bindings are traversed independently.

Each lookup uses the original cache; binding adds no storage, key identity, or snapshot depth. Inspect or clear the original cache, since bindings expose no count, capacity, or clearing operations.

Use ``SizeDependencies/at(_:)`` for dependency-only mapping. That descriptor retains dependency readers without retaining the cache, binding, measurement closure, or entries. Parent child-description capture has the same retention rule. A bound lookup handle itself retains its original cache, so the calculation must capture the handles it calls. The graph is immutable and acyclic by construction; its snapshot depth is checked against ``SizeDependencies/maximumDepth``.

## Ownership and completeness

A view, screen-owned bundle, or intentionally shared static property can own caches. Composition imposes no ownership model. Each reference owns one bounded result cache; sharing the reference shares storage and recency. Clearing a parent clears only that cache, and child clearing or eviction does not invalidate a semantically valid parent result. Clear every affected cache if an undeclared external change invalidates results, or represent that change in selected values.

Snapshots retain full equality-checkable values, concrete types, and child structure. They do not deep-copy mutable references. Project immutable values, including through computed properties, and keep all result-relevant state consistent between selection and computation. The configured closure is retained; user captures and selected reference values can retain objects, but roots passed to lookup are not implicitly retained. The API observes no changes and schedules no UIKit layout.

Each cache uses the generic core's bounded LRU. Zero capacity disables storage. Same-cache measurement reentry, including count inspection or clearing during the recipe, fails a descriptive precondition before accessing storage. Recursive calls to distinct caches are supported.

Do not call a native-fitting cache from the measured view's own `sizeThatFits(_:)` override: a miss invokes the override again. Supply a custom recipe for that integration. Neither initializer discovers undeclared inputs or makes mutable `Hashable` aliases stable.

## Topics

### Measure and reuse

- ``SizeCache``
- ``SizeCacheBinding``

### Map and inspect dependencies

- ``SizeDependencies``
