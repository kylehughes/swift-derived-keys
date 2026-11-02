# ``DerivedKeysUIKit``

Reuse complete UIKit layout results from captured inputs and fitting proposals.

## Overview

Use this module to cache complete layout results from explicit inputs and fitting proposals. For a key-path sizing API with configured measurement closures and recursive child caches, use the separate `DerivedKeysUI` product.

A frame-based view often calculates the same layout while answering a fitting request and assigning child frames. Retain a ``LayoutCache`` on the main actor and cache an immutable result containing the fitted size and frames. Views running the same algorithm can explicitly share the cache.

## Capture inputs and fitting proposals

Declare a distinct operation type for each layout algorithm. Capture the content in a hashable input and any environment values the algorithm reads in a hashable context. The cache adds the effective ``FittingProposal`` to the request automatically and passes those captured values to its synchronous calculation. It retains keys and results, never the callback. Equality must remain stable for stored keys, and results must retain their meaning through external aliases.

Use ``FittingProposal/init(fitting:)`` to validate a UIKit fitting size. Its greatest-finite-magnitude sentinel represents an unconstrained dimension; NaN, infinity, and negatives throw. ``FittingProposal/fittingSize`` bridges back to UIKit without quantizing finite bounds. The cache does not impose rounding, clamping, text measurement, or frame assignment.

## Measure with a retained cache

Retain a measurer in a view or another main-actor owner. Its cache survives individual requests. This label calculation reads only the captured text, proposal, and font size; all other label measurement settings stay fixed:

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

Pass the retained `BadgeMeasurer` to `measureBadge(using:)` for successive requests. A new measurer per request would discard reusable entries.

## Reuse results for sizing and layout

Use the same effective proposal for sizing and layout when both operations perform the same calculation. A view that deliberately computes natural height can use a width-only proposal in both paths. Capture every font, trait, inset, and other input the algorithm reads; main-actor isolation does not make an incomplete dependency selection correct. Changing content and scheduling layout remain application responsibilities.

## Compose parent layout keys

For parent layouts, compose complete ``LayoutKey`` values returned by ``LayoutCache/key(for:proposal:context:)`` with parent-only inputs. Keep child keys intact so operation, version, proposal, input, and context remain represented.

## Topics

### Describe fitting bounds

- ``FittingDimension``
- ``FittingProposal``
- ``FittingProposalError``

### Capture layout requests

- ``LayoutInputs``
- ``LayoutKey``

### Reuse layout results

- ``LayoutCache``
