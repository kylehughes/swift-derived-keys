# Caching a custom UIKit layout

Use `LayoutCache` from `DerivedKeysUI` when you want to cache complete layout results—such as an overall `CGSize` alongside subview frames—from explicit `Hashable` inputs. If you only need key-path-driven `CGSize` caching, start with [SizeCache](Size-Caches.md). The shared rules for complete, stable inputs are in the [cache contract](../Documentation/DerivedKeysUI.docc/CacheContract.md).

The [compiled `LabelView` example](../Sources/DerivedKeysUIExample/LabelView.swift) caches a `Layout` struct holding an overall size and a label frame. Because `DerivedKeysUIExample` is an example target rather than a package product, copy and adapt that pattern in your own app.

## Capture one request

`LayoutCache<Operation, Input, Context, Value>` is a main-actor reference type. Declare a distinct operation enum for each layout algorithm, capture its content in a `Hashable` input value, and capture any environment values the algorithm reads in a `Hashable` context. The cached `Value` can be `CGSize` or an immutable struct containing all the frames and sizes your view needs.

Retain the cache in your view or another main-actor owner to reuse results across layout passes. Here `BadgeMeasurer` owns a single cache, measures from the callback's captured `text`, `proposal`, and `style`, and keeps the rest of the label's configuration fixed:

```swift
import DerivedKeysUI
import UIKit

enum BadgeLayout {}

struct BadgeStyle: Hashable {
    let fontSize: CGFloat
}

@MainActor
final class BadgeMeasurer {
    private let cache = LayoutCache<BadgeLayout, String, BadgeStyle, CGSize>(capacity: 32)

    func size(of text: String, toFit fittingSize: CGSize, style: BadgeStyle) throws -> CGSize {
        let proposal = try FittingProposal(fitting: fittingSize)
        return cache.value(for: text, proposal: proposal, context: style) {
            text, proposal, style in
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: style.fontSize)
            label.numberOfLines = 1
            label.textAlignment = .left
            label.semanticContentAttribute = .forceLeftToRight
            return label.sizeThatFits(proposal.fittingSize)
        }
    }
}

@MainActor
func measureBadge(using measurer: BadgeMeasurer) throws -> CGSize {
    try measurer.size(
        of: "Unread",
        toFit: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude),
        style: BadgeStyle(fontSize: 17)
    )
}
```

Keep one `BadgeMeasurer` alive across calls to `measureBadge(using:)`; creating a new measurer per request discards the cached entries.

`LayoutCache` automatically includes the effective fitting proposal in its key, then passes the captured `input`, `proposal`, and `context` to the calculation closure. Read only from those arguments and fixed configuration inside the closure—reading uncaptured view or model properties bypasses the key.

Capture actual text and every metric-affecting style rather than a bare model ID: resolved fonts, line limits, insets, layout direction, relevant traits, and display scale if your rounding depends on it. Use an empty (`Void`) context only when no variable environment value affects the layout. Project mutable objects into stable values, as described in the [cache contract](../Documentation/DerivedKeysUI.docc/CacheContract.md#select-stable-values).

## Match fitting to layout

`FittingDimension(points:)` accepts finite, nonnegative bounds and rejects infinity; use `.unconstrained` when an axis has no bound. `FittingProposal(fitting:)` maps each `CGFloat.greatestFiniteMagnitude` or positive-infinity dimension to `.unconstrained`, and `proposal.fittingSize` maps `.unconstrained` back to `CGFloat.greatestFiniteMagnitude` for UIKit. NaN, negative infinity, and negative dimensions throw `FittingProposalError.invalidDimension`. Zero is a valid finite bound.

Because the `CGSize` bridge reserves `CGFloat.greatestFiniteMagnitude` as its unconstrained sentinel, a manually constructed `FittingDimension(points: .greatestFiniteMagnitude)` becomes `.unconstrained` when round-tripped through `CGSize` and `FittingProposal(fitting:)`. All other finite bounds are preserved without quantization.

`LayoutCache` neither clamps nor rounds the result your closure returns. Pass the proposal your layout actually uses: if your algorithm ignores proposed height, construct a width-only proposal (with unconstrained height) in both `sizeThatFits(_:)` and `layoutSubviews()`. Keying `sizeThatFits(_:)` with an unconstrained height and `layoutSubviews()` with `bounds.height` produces two different keys and misses the cache.

In the compiled `LabelView` example, the layout fills a finite requested width and returns natural height, and the parent view assigns the fitted frame before normal UIKit layout. If a caller asks for natural width with an unconstrained width proposal and then assigns that finite width to `frame`, the following `layoutSubviews()` pass sees a finite width and therefore looks up a different key. Widths at or below twice the fixed horizontal padding produce zero-width text, and invalid widths return `.zero` at the view boundary. Those choices belong to `LabelView`, not `LayoutCache`.

## Share and compose

You can store a `LayoutCache` per view or inject a shared instance into multiple equivalently configured views. Shared references share entries, capacity, and LRU recency order. `LabelView` accepts an injected cache for explicit sharing:

```swift
// With the example LabelView copied into your app:
let cache = LabelView.Cache(capacity: 64)
let first = LabelView(text: "Shared content", cache: cache)
let second = LabelView(text: "Shared content", cache: cache)
```

The [full source](../Sources/DerivedKeysUIExample/LabelView.swift) includes this initializer along with calculation counters used by tests. Because view identity is not part of the key, two views with equal captured inputs and proposals hit the same entry. A reused view whose text changes looks up a different entry, and changing inputs from A to B and back to A reuses A's result if its entry is still retained.

When composing a parent layout from child layouts, call `key(for:proposal:context:)` on each child cache. It returns a `LayoutKey` (a `RequestKey` whose `LayoutInputs` hold the complete child input and proposal). Embed those complete child keys in the parent's `Hashable` input alongside the parent's own layout properties, rather than combining integer hashes or measured child sizes. Separate each layout algorithm with its own `Operation` type. The [text-component example](Text-Component.md) shows this pattern with independently cached children and an optional child key.

## Ownership and invalidation

`capacity` counts retained entries, not bytes, and `0` disables storage. Hits promote entries to most recently used; misses that return normally insert the new entry and evict the least recently used entry when full. Throwing calculations propagate their error without inserting or evicting, and cached optional `nil` results are treated as hits. `removeValue(for:)` removes a single complete `LayoutKey`, while `removeAll()` clears all entries for every owner sharing that cache reference.

Entries retain their captured inputs, context, and results, whereas the calculation closure is nonescaping and is never stored. Because caller-supplied inputs or results can retain views or other objects if you put references inside them, store immutable value-type geometry in your layout structs. Reentering the same `LayoutCache` while a calculation is running—including reading `count` or removing entries through another reference—fails a precondition.

Updating content, requesting a layout result, calling `setNeedsLayout()`, and updating a container's frame remain separate application steps. `LayoutCache` never observes models or schedules UIKit layout. When text changes, the view can call `setNeedsLayout()` without clearing old entries, and its container still needs to refit the view when the desired outer size changes.
