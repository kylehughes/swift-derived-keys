# Reuse layout results

Reuse complete UIKit layout results from captured inputs and fitting proposals.

## Overview

A frame-based view often computes the same geometry in `sizeThatFits(_:)` and again in `layoutSubviews()`. Retain a ``LayoutCache`` on the main actor to cache an immutable layout value—such as a struct holding both the fitted `CGSize` and child `CGRect` frames—and reuse it whenever the captured inputs and effective proposal match. Multiple views that run the same layout algorithm can share one ``LayoutCache`` reference.

Use ``SizeCache`` instead when you want key-path dependency selection and recursive child caches, or ``MainActorResultCache`` for arbitrary main-actor calculations that do not take a fitting proposal.

## Capture inputs and fitting proposals

Define a distinct `Operation` type for each layout algorithm, capture the view's content in a `Hashable` input, and capture any environment values the algorithm reads in a `Hashable` context. ``LayoutCache`` combines those with the effective ``FittingProposal`` to form the key, and passes the captured input, proposal, and context into the calculation closure on a miss. The cache retains keys and results, never the calculation closure. As <doc:CacheContract> describes, your input and context must be complete and stable.

Convert a UIKit target size into a proposal with ``FittingProposal/init(fitting:)``:

- Negative values, NaN, and negative infinity throw ``FittingProposalError/invalidDimension``.
- `CGFloat.greatestFiniteMagnitude` and positive infinity both map to ``FittingDimension/unconstrained``.
- ``FittingProposal/fittingSize`` converts the proposal back to a `CGSize`, using `CGFloat.greatestFiniteMagnitude` for unconstrained axes and keeping finite dimensions exact without quantization.

``LayoutCache`` does not round, clamp, measure text, or assign view frames.

## Measure with a retained cache

Store the cache (or its owning helper) on a view or screen controller so entries survive across requests. In this example, the calculation reads only the captured `text`, `proposal`, and `style.fontSize`, and sets every other `UILabel` property to a constant:

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

Pass the retained `BadgeMeasurer` to `measureBadge(using:)` across calls; creating a new measurer per call would discard the cached entries.

## Reuse results for sizing and layout

To hit the same entry in `sizeThatFits(_:)` and `layoutSubviews()`, pass the same effective proposal from both methods. For example, a view whose height flows from its available width can pass a width-constrained, height-unconstrained proposal in both `sizeThatFits(_:)` and `layoutSubviews()` (using `bounds.width`). Include every font, trait, inset, and other variable input the layout reads, and trigger `setNeedsLayout()` yourself when model state changes.

Reentering the same ``LayoutCache`` while its calculation closure is running fails a precondition—including reading `count`, removing an entry, or clearing the cache.

## Compose parent layout keys

When a parent layout key depends on child layout inputs, build each child's ``LayoutKey`` with ``LayoutCache/key(for:proposal:context:)`` and embed the complete ``LayoutKey`` inside the parent's input struct alongside any parent-only properties. Keeping the full ``LayoutKey`` intact preserves each child's operation type, proposal, input, and context.
