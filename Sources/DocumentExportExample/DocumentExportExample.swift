import DerivedKeys

/// Exports only content and options; presentation state does not affect output.
@main
struct DocumentExportExample {
    enum ExportOperation {}

    enum Format: Hashable {
        case plainText
        case markdown
    }

    struct Document {
        let paragraphs: [String]
        var selectedParagraph: Int?
        var scrollOffset: Double
    }

    struct ExportInput: Hashable {
        let paragraphs: [String]
        let format: Format
        let includesHeading: Bool
    }

    static func main() {
        let projection = KeyProjection(operation: ExportOperation.self) { (input: ExportInput) in
            DerivedKey("export", children: input)
        }
        var cache = MemoizationCache<RequestKey<ExportOperation, DerivedKey<ExportInput>, String>, String>(capacity: 8)
        var computations = 0
        var document = Document(paragraphs: ["Content is shared.", "Selection is not exported."], scrollOffset: 0)

        func export(_ document: Document, format: Format) -> String {
            let input = ExportInput(paragraphs: document.paragraphs, format: format, includesHeading: true)
            let key = projection.key(for: input, context: "UTF-8")
            return cache.value(for: key) {
                computations += 1
                let heading =
                    input.includesHeading ? (input.format == .markdown ? "# Document\n\n" : "Document\n\n") : ""
                return heading + input.paragraphs.joined(separator: "\n\n")
            }
        }

        let first = export(document, format: .plainText)
        document.selectedParagraph = 1
        document.scrollOffset = 200
        let afterScrolling = export(document, format: .plainText)
        let markdown = export(document, format: .markdown)
        precondition(first == afterScrolling && computations == 2)
        print(markdown)
        print("Three requests, \(computations) computations, \(cache.count) retained entries.")
    }
}
