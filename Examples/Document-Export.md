# Reusing an export after a UI change

This example uses the generic `DerivedKeys` API to reuse a plain-text export after selection changes. The exporter retains its cache across requests and captures the content and format once per request. It calculates from that same snapshot. Selection is absent from the key because the exporter never reads it.

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

Run `swift run DocumentExportExample` from the repository for the fuller ordered-paragraph exporter. It projects document content, format, and export options while ignoring selection and scrolling. The [generic API guide](Generic-Core.md) covers dependency selection and cache ownership beyond this example.
