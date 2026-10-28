# ``DerivedKeys``

Capture the dependencies of a calculation as an immutable, hashable request.

## Overview

A model can change without changing the result of every calculation that consumes it. An export depends on document content and export options; selection and scroll position can be irrelevant. A measurement depends on content, typography, and fitting bounds even when the entity's ID stays the same.

Define that narrower equivalence separately from the model's general-purpose equality. Capture one coherent input state, select its dependencies, form a request key, and calculate from the same capture on a cache miss. Equal keys must imply interchangeable results. The library cannot infer whether your selection includes every relevant input.

Use ``RequestKey`` with a small `Hashable` struct for fixed schemas. ``OriginalKey``, ``DerivedKey``, and ``KeyPair`` add labeled typed composition. ``KeySource`` supports heterogeneous runtime graphs, while ``MemoizationCache`` demonstrates bounded synchronous reuse.

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
