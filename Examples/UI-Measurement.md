# Caching a custom UIKit layout

Use `DerivedKeysUIKit` to cache complete layout results, including sizes and frames, from explicit inputs. Add the product to your app target and import it alongside UIKit. For the shorter key-path sizing API, start with [SizeCache](Size-Caches.md).

The [compiled `LabelView` example](../Sources/DerivedKeysUIExample/LabelView.swift) caches a `Layout` containing an overall size and a label frame. The example target is not a package product; copy and adapt the view in your app.

## Capture one request

`LayoutCache<Operation, Input, Context, Value>` is a main-actor reference type. Declare a distinct operation enum for each layout algorithm, capture its content in a `Hashable` input, and capture any environment values the algorithm reads in a `Hashable` context. The result can be `CGSize` or an immutable structure containing all the frames and sizes your view needs.

Retain the cache in your view or another main-actor owner to reuse results across requests. This measurer owns one cache, uses the callback's captured text, proposal, and style, and keeps the remaining label configuration fixed:

```swift
import DerivedKeysUIKit
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

Retain one `BadgeMeasurer` and pass it to `measureBadge(using:)` for successive requests. Creating a measurer for each request discards the entries that could be reused.

The cache automatically includes the effective fitting proposal in its key, then supplies the captured input, proposal, and context to the calculation. Measure from those arguments. Reading other mutable view or model properties inside the callback can produce an incomplete key even on the main actor.

Capture actual text and metric-affecting styles, not only a model ID. Include resolved fonts, line limits, insets, layout direction, or relevant traits when the algorithm consumes them. Include display scale if your own rounding depends on it. An empty context is appropriate only when no variable environment affects the calculation. Hashable reference values can still have mutable aliases; project stable values and keep cached results stable too.

## Match fitting to layout

`FittingDimension(points:)` accepts finite nonnegative bounds. `.unconstrained` represents the absence of a bound. `FittingProposal(fitting:)` maps each `CGFloat.greatestFiniteMagnitude` dimension to `.unconstrained`; `fittingSize` maps it back for UIKit. NaN, infinity, and negative dimensions throw `FittingProposalError.invalidDimension`. Zero is a real bound.

The bridge reserves the greatest finite value as a sentinel. A manually constructed finite dimension with that exact value becomes unconstrained if converted through `CGSize` and back. Other finite bounds are preserved without quantization.

The cache neither clamps nor rounds a result. Pass the proposal you actually use for measurement. If your algorithm intentionally ignores height, construct a width-only proposal in both `sizeThatFits(_:)` and `layoutSubviews()`; keying one with natural height and the other with `bounds.height` would describe different requests.

The compiled `LabelView` example fills a finite requested width and returns natural height. A parent assigns the fitted frame before normal UIKit layout. A natural-width request uses an unconstrained proposal, so assigning its finite result produces a distinct request on the following layout pass. Widths at or below twice the fixed padding yield zero-width text; invalid widths return zero at the view boundary. These are example policies, not rules imposed by the library.

## Share and compose

Retain a cache per view, or inject one cache into several equivalent views. References share entries, capacity, and LRU recency. The example view supports explicit sharing:

```swift
// With the example LabelView copied into your app:
let cache = LabelView.Cache(capacity: 64)
let first = LabelView(text: "Shared content", cache: cache)
let second = LabelView(text: "Shared content", cache: cache)
```

The [full source](../Sources/DerivedKeysUIExample/LabelView.swift) includes this initializer and calculation counters. Two views with equal captured inputs and proposals can share a result without including view identity. A reused view with changed text requests a different entry. Changing inputs from A to B and back to A can reuse A's result while its entry remains retained.

Use `key(for:proposal:context:)` when composing child layouts. It returns `LayoutKey`, a core `RequestKey` whose `LayoutInputs` contain the complete input and proposal. Store complete child keys in the parent's hashable input alongside parent-only values, rather than composing hash integers or measured sizes. Distinct operation types and the cache's fixed `version` separate algorithms. The [text/button demonstration](Text-Component.md) illustrates independently cached children and an optional child dependency.

## Ownership and invalidation

Capacity counts entries, not bytes. Zero disables storage. Hits promote entries; successful misses insert and evict the least recently used entry when necessary. Throwing calculations propagate without insertion or eviction, and cached optional `nil` results are hits. `removeValue(for:)` accepts a complete key; `removeAll()` clears entries for every owner sharing that cache.

Entries retain inputs, context, and results. The callback is nonescaping and is never stored. Caller-provided values can themselves retain views or other objects, so use immutable geometry results when that is what the cache should own. Do not reenter the same cache during a calculation, including through another reference.

Changing content, requesting a new layout result, scheduling UIKit layout, and updating a container's frame are separate application actions. The library observes no models and schedules no layout. A text change can call `setNeedsLayout()` without clearing old entries; the parent still needs to refit the view when its desired outer size changes.
