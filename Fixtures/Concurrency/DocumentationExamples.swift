import DerivedKeys

// Mirrors Examples/Generic-Core.md.
func documentationProjectionExample() {
    enum ExportOperation {}

    struct Document {
        var text: String
        var uppercase: Bool
        var isSelected: Bool
    }

    struct ExportInput: Hashable {
        let text: String
        let uppercase: Bool
    }

    let projection = KeyProjection(operation: ExportOperation.self) { (document: Document) in
        ExportInput(text: document.text, uppercase: document.uppercase)
    }
    var document = Document(text: "Hello", uppercase: true, isSelected: false)
    let first = projection.key(for: document, context: "plain-text")
    document.isSelected = true
    let selected = projection.key(for: document, context: "plain-text")
    assert(first == selected)
    document.uppercase = false
    let lowercase = projection.key(for: document, context: "plain-text")
    assert(first != lowercase)
}

// Mirrors Examples/Generic-Core.md.
func documentationRuntimeSourceExample() throws {
    enum RuntimeExportOperation {}

    struct RuntimeExportInput {
        let text: String
        let uppercase: Bool
    }

    let text = KeySource<RuntimeExportInput>("text") { $0.text }
    let options = KeySource<RuntimeExportInput>("uppercase") { $0.uppercase }
    let source = try KeySource("export", children: [text, options])
    let input = RuntimeExportInput(text: "Hello", uppercase: true)
    let key = RequestKey(
        operation: RuntimeExportOperation.self,
        dependencies: source.snapshot(for: input),
        context: "plain-text"
    )
    assert(key.dependencies == source.snapshot(for: input))
}

// Mirrors Examples/Generic-Core.md.
func documentationLiveProviderExample() {
    final class DocumentStore {
        var text: String

        init(text: String) {
            self.text = text
        }
    }

    func captureLiveText() {
        let store = DocumentStore(text: "Hello")
        let source = KeySource<Void>("text", provider: { store.text })
        let first = source.snapshot(for: ())
        store.text = "Goodbye"
        let edited = source.snapshot(for: ())
        assert(first != edited)
        store.text = "Hello"
        assert(first == source.snapshot(for: ()))
    }

    captureLiveText()
}

// Mirrors DerivedKeys.docc/DerivedKeys.md.
func documentationCoreExportExample() {
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
