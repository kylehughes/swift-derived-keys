import DerivedKeys

// Mirrors the complete sample in Examples/Document-Export.md and README.md.
func readmeGenericExample() {
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
    let second = exporter.export(document, uppercase: false)  // Retained cache hit.
    let capitals = exporter.export(document, uppercase: true)  // Different key.
    assert(first == second && capitals == "HELLO")
}
