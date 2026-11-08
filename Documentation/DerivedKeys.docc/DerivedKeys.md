# ``DerivedKeys``

Capture the dependencies of a calculation as an immutable, hashable request.

## Overview

A model can change without changing the result of every calculation that consumes it. A view layout depends on content, typography, and fitting bounds even when the entity's ID stays the same; a paint-only color change can leave its geometry unchanged. An export depends on document content and export options while selection and scroll position can be irrelevant.

Define a key for the inputs a particular calculation reads, independently of the model's general-purpose `Equatable` or `Hashable` conformance. Capture a consistent input state, build a request key from its relevant properties, and compute the result from that same captured input on a cache miss. Equal keys must imply interchangeable results. The library compares only what you select; it cannot determine whether you included every relevant input.

## Reuse an export

Retain a cache across requests, and capture the values the exporter reads. This exporter selects text and the uppercase option; changing selection leaves its request key equal.

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

The cache hit skips the calculation closure. The uppercase request has different dependencies and calculates a separate result. Keep each export's key and calculation based on the same captured input.

## Choose the API for your dependencies

Start with <doc:DependencyDesign> to choose complete dependencies. Use ``ResultCache`` to bind key paths and a nonthrowing calculation once, then call `value(for:)` with each input. Named tuple inputs combine values without a custom request type; select every relevant tuple field explicitly. The cache is a value type, and copied caches mutate their entries independently.

Use ``RequestKey`` with a small `Hashable` struct for fixed schemas. ``OriginalKey``, ``DerivedKey``, and ``KeyPair`` add labeled typed composition. ``KeySource`` supports heterogeneous runtime graphs, and ``MemoizationCache`` stores results for bounded synchronous reuse, including throwing calculations.

For UIKit view sizing, `DerivedKeysUI` provides `SizeCache`, which reads selected key-path dependencies and composes child caches on the main actor. That module's `MainActorResultCache` binds an arbitrary-result calculation to a shared main-actor cache. To cache custom layout results with automatic fitting-proposal keys, such as fitted sizes alongside child frames, use `LayoutCache` in `DerivedKeysUIKit`. `DerivedKeys` itself depends only on the Swift standard library and has no main-actor requirement.

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

- ``ResultCache``
- ``MemoizationCache``
