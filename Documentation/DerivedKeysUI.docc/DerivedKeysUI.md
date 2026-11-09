# ``DerivedKeysUI``

Cache view measurements by selected key paths, and compose child caches to reuse a whole layout size.

## Overview

Create a ``SizeCache`` once on the main actor and retain it across requests. For a leaf `UIView`, the UIKit initializer takes key paths to the `Hashable` properties that affect sizing and calls the view's `sizeThatFits(_:)` on a miss. For parents with child caches, custom measurement recipes, or non-UIKit roots, use the closure initializer—the only initializer that accepts children. Both initializers allow zero key paths.

Select every variable property the measurement reads. In the example below, all other `UILabel` properties stay at their fixed defaults; <doc:CacheContract> explains why unselected settings must not vary:

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

Retain the cache returned by `makeTextSizes()` on a view or another main-actor owner, and pass it to `measureText(using:)` on each sizing pass.

Each `size(of:toFit:)` lookup takes the current root and a fitting proposal. The root itself does not need to be `Hashable` or `Sendable` and is not stored in the key. Both proposal axes enter the key automatically; see <doc:CacheContract> for how unconstrained (`greatestFiniteMagnitude` and `+infinity`), zero, and invalid dimensions behave.

## Compose child measurements

To cache a container layout, create a parent ``SizeCache`` with the closure initializer and list its children in `children:`. Every declared child's selected values become part of the parent's key, and the parent's recipe measures children through those same handles. A parent hit returns the cached size immediately and skips the recipe and all child lookups. On a parent miss, the recipe runs and each child lookup can still hit its own cache independently. Debug builds assert if a recipe measures through an undeclared ``SizeCache``; see <doc:CacheContract> for the check and its opt-out.

When a child cache has a different root type than the parent, map it with `child.bound(to: \Parent.child)`. The returned ``SizeCacheBinding`` serves both as the child description for `children:` and as the handle you call with the parent root inside the recipe. Bindings can be chained and forward lookups directly to the underlying ``SizeCache`` without adding storage.

Here `PairView` stacks a title and subtitle vertically. Both labels share one `UILabel` cache because they keep the same fixed defaults apart from their selected `text`, `font`, and `numberOfLines`:

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

Construct the parent once with `makePairSizes(titleSizes: makeTextSizes())` and reuse it across `measurePair(using:)` calls.

## Cache other results

When a main-actor calculation returns something other than a fitted `CGSize`—such as a TextKit line count—use ``MainActorResultCache``. It keys only the key paths you select, with no implicit fitting proposal or child composition. Pass a named tuple when the recipe reads multiple inputs. To chain stages, look up the first cache's result explicitly and pass it into the next cache, unlike ``SizeCache`` children whose raw dependencies enter the parent key without evaluating child results first.

To cache complete layout outputs—such as a fitted size paired with child frames—from explicit `Hashable` inputs, see <doc:LayoutCaches>.

## Topics

### Understand the contract

- <doc:CacheContract>

### Measure and reuse

- ``SizeCache``
- ``SizeCacheBinding``
- ``SizeDependencies``

### Cache other results

- ``MainActorResultCache``

### Reuse layout results

- <doc:LayoutCaches>
- ``LayoutCache``
- ``LayoutKey``
- ``LayoutInputs``

### Describe fitting bounds

- ``FittingDimension``
- ``FittingProposal``
- ``FittingProposalError``
