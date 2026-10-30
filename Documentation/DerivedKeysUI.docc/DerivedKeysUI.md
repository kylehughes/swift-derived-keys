# ``DerivedKeysUI``

Cache measurements by selected key paths, then compose child caches to reuse an entire layout size.

## Overview

Create a ``SizeCache`` once in a retained main-actor owner. Its initializer binds heterogeneous hashable key paths and one synchronous measurement closure. A lookup supplies the current root and fitting proposal; the root itself needs neither Hashable nor Sendable conformance and is not implicitly part of the key.

```swift
import DerivedKeysUI
import UIKit

@MainActor
func makeTextSizes() -> SizeCache<UILabel> {
    SizeCache<UILabel>(dependingOn: \.text, \.font, \.numberOfLines, capacity: 256) { label, proposal in
        label.sizeThatFits(proposal)
    }
}
```

This example assumes the label's other measurement settings are fixed. Select every property the actual calculation reads. The facade automatically keys both fitting dimensions, normalizes signed zero, and supplies that same normalized proposal to the calculation. Finite nonnegative values are accepted, including the greatest finite value as an unbounded sentinel; NaN, infinity, and negative proposals fail descriptive preconditions. Measurement results are not rounded or clamped by the cache.

## Compose child measurements

Pass child caches in `children:` when creating a parent. A parent hit skips its calculation and every child result lookup. A parent miss runs the configured calculation, where each child lookup can independently hit. Transform proposals in the calculation and declare any values that affect the transformation. Children key the actual proposals they receive. All declared children participate in the dependency snapshot even when a branch will not measure them.

Use ``SizeDependencies/at(_:)`` for a child with a different root type. The descriptor retains the child's immutable dependency-reading recipe, without copying results or retaining child result storage. Call the original child with the mapped root in the parent calculation. Capture those handles in the closure. The graph is immutable and acyclic by construction; its snapshot depth is checked against ``SizeDependencies/maximumDepth``. Distinct root bindings are traversed independently.

## Ownership and completeness

A view, screen-owned bundle, or intentionally shared static property can own caches. Composition imposes no ownership model. Each reference owns one bounded result cache; sharing the reference shares storage and recency. Clearing a parent clears only that cache, and child clearing or eviction does not invalidate a semantically valid parent result. Clear every affected cache if an undeclared external change invalidates results, or represent that change in selected values.

Snapshots retain full equality-checkable values, concrete types, and child structure. They do not deep-copy mutable references. Project immutable values, including through computed properties, and keep all result-relevant state consistent between selection and computation. The configured closure is retained; user captures and selected reference values can retain objects, but roots passed to lookup are not implicitly retained. The API observes no changes and schedules no UIKit layout.

Each cache uses the generic core's bounded LRU. Zero capacity disables storage. Same-cache measurement reentry, including count inspection or clearing during the recipe, fails a descriptive precondition before accessing storage. Recursive calls to distinct caches are supported.

## Topics

### Measure and reuse

- ``SizeCache``

### Map and inspect dependencies

- ``SizeDependencies``
