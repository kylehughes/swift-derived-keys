# ``DerivedKeys``

Capture the dependencies of a calculation as an immutable, hashable request.

## Overview

A model often changes without affecting every calculation that reads it. A view's geometry depends on text, typography, and fitting bounds even when the model's ID is unchanged, while a paint-only color change leaves geometry alone. A document export depends on content and format options, not selection state or scroll offset.

Instead of altering a model's general-purpose `Equatable` or `Hashable` conformance, project only the inputs that a specific calculation reads. Capture a consistent input state, build a key from its relevant values, and run the calculation from that same captured input on a miss. Equal keys must imply interchangeable results: the library compares only what you select and cannot verify whether you omitted an input the calculation reads.

Use ``ResultCache`` to bind key paths and a recipe directly, pass explicit keys to ``MemoizationCache`` for bounded LRU reuse, or use the key types with your own storage.

## Reuse an export

Retain the cache across requests and capture the values the exporter reads. Here the exporter selects `text` and `uppercase`, so toggling `isSelected` produces the same request key and hits the cache:

```swift
import DerivedKeys

enum ExportOperation {}

struct Document {
    var text: String
    var isSelected: Bool
}

struct ExportInput: Hashable {
    let text: String
    let uppercase: Bool
}

struct Exporter {
    private var cache = MemoizationCache<
        RequestKey<ExportOperation, ExportInput, String>, String
    >(capacity: 32)

    mutating func export(_ document: Document, uppercase: Bool) -> String {
        let input = ExportInput(text: document.text, uppercase: uppercase)
        let key = RequestKey(
            operation: ExportOperation.self,
            dependencies: input,
            context: "plain-text"
        )
        return cache.value(for: key) {
            input.uppercase ? input.text.uppercased() : input.text
        }
    }
}

var exporter = Exporter()
var document = Document(text: "Hello", isSelected: false)
let first = exporter.export(document, uppercase: false)
document.isSelected = true
let second = exporter.export(document, uppercase: false) // Retained cache hit.
let capitals = exporter.export(document, uppercase: true) // Different key.
assert(first == second && capitals == "HELLO")
```

A hit returns the stored output without running the closure. Passing `uppercase: true` changes the dependencies and computes a separate entry. Always build the key and compute the miss result from the same captured `input`.

## Choose the API for your dependencies

Read <doc:DependencyDesign> first to decide which inputs belong in a key. Then pick the surface that matches your calculation:

- **Key-path recipe caching:** ``ResultCache`` binds selected key paths and a nonthrowing recipe once, then looks up results with `value(for:)`. Pass a named tuple when a calculation takes several inputs, and select every relevant tuple field. `ResultCache` is a value type whose copies mutate independently; it takes ordinary key paths and closures with no `Sendable` requirement, so a `@MainActor` type can own one directly.
- **Explicit request keys and throwing calculations:** Pair ``RequestKey`` (or ``KeyProjection``) and a small `Hashable` dependency struct with ``MemoizationCache`` when you want explicit keys or throwing calculations. ``OriginalKey``, ``DerivedKey``, and ``KeyPair`` add labeled, static composition, while ``KeySource`` and ``DependencySnapshot`` build heterogeneous runtime dependency graphs.
- **Main-actor UI sizing and layout:** Use the `DerivedKeysUI` module for UIKit. It provides `SizeCache` (which reads key paths on the main actor, keys the fitting proposal automatically, and composes child caches), `MainActorResultCache` (for shared main-actor result caches), and `LayoutCache` (for complete layout outputs such as fitted sizes with child frames). `DerivedKeys` itself depends only on the Swift standard library and has no main-actor requirement.

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
- ``DependencySnapshot``

### Reuse a result

- ``ResultCache``
- ``MemoizationCache``
