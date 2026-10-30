# ``DerivedKeys``

Capture the dependencies of a calculation as an immutable, hashable request.

## Overview

A model can change without changing the result of every calculation that consumes it. A view layout depends on content, typography, and fitting bounds even when the entity's ID stays the same; a paint-only color change can leave its geometry unchanged. An export depends on document content and export options while selection and scroll position can be irrelevant.

Define when results are interchangeable separately from the model's general-purpose equality. Capture one coherent input state, select its dependencies, form a request key, and calculate from the same capture on a cache miss. Equal keys must imply interchangeable results. The library cannot infer whether your selection includes every relevant input.

Start with <doc:DependencyDesign> to choose complete dependencies. Use ``RequestKey`` with a small `Hashable` struct for fixed schemas. ``OriginalKey``, ``DerivedKey``, and ``KeyPair`` add labeled typed composition. ``KeySource`` supports heterogeneous runtime graphs, and ``MemoizationCache`` stores results for bounded synchronous reuse.

For the short sizing API, `DerivedKeysUI` binds key-path dependencies and a measurement recipe in a recursive `SizeCache`. The separate `DerivedKeysUIKit` product retains validated fitting proposals and a main-actor `LayoutCache` for caller-defined sizes and frames. The generic core remains standard-library-only and has no main-actor requirement.

## Topics

### Choose a dependency projection

- <doc:DependencyDesign>
- ``KeyProjection``
- ``RequestKey``

### Compose typed values

- ``OriginalKey``
- ``DerivedKey``
- ``KeyPair``

### Evaluate runtime sources

- ``KeySource``
- ``KeyValueProvider``
- ``DependencySnapshot``

### Reuse a result

- ``MemoizationCache``
