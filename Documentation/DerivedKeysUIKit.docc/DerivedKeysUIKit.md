# ``DerivedKeysUIKit``

Reuse complete UIKit layout results from captured inputs and fitting proposals.

## Overview

For a key-path sizing API with configured measurement closures and recursive child caches, use the separate `DerivedKeysUI` product. This module provides the explicit-input API for arbitrary complete layout results.

A frame-based view often calculates the same layout while answering a fitting request and assigning child frames. Retain a ``LayoutCache`` on the main actor and cache an immutable result containing the fitted size and frames. The same cache can be explicitly shared across views running the same algorithm.

Declare a distinct operation type, capture the content in a hashable input, and capture the consumed environment in a hashable context. The cache adds the effective ``FittingProposal`` to the request automatically and passes those captured values to its synchronous calculation. It retains keys and results, never the callback. Equality must remain stable for stored keys, and results must retain their meaning through external aliases.

Use ``FittingProposal/init(fitting:)`` to validate UIKit geometry. Its greatest-finite-magnitude sentinel represents an unconstrained dimension; NaN, infinity, and negatives throw. ``FittingProposal/fittingSize`` bridges back to UIKit without quantizing finite bounds. The cache does not impose rounding, clamping, text measurement, or frame assignment.

Use the same effective proposal for sizing and layout when both operations perform the same calculation. A view that deliberately computes natural height can use a width-only proposal in both paths. Capture every consumed font, trait, inset, and other input; main-actor isolation does not make an incomplete dependency selection correct. Changing content and scheduling layout remain application responsibilities.

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
