# Reusing an export after a UI change

This example uses the lower-level `DerivedKeys` APIs to reuse a plain-text export when UI selection changes. `Exporter` retains its `MemoizationCache` across requests, captures the document text and export format once per call, and runs its calculation from that captured `ExportInput`. Because the exporter never reads `isSelected`, selection state is omitted from the key.

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

Run `swift run DocumentExportExample` from the repository root to execute the fuller multi-paragraph exporter, which projects document content, format, and export options while ignoring selection and scroll position. See the [generic API guide](Generic-Core.md) for more on dependency selection and cache ownership.
