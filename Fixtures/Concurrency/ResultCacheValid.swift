func resultCacheExamples() {
    var scalar = ResultCache<Int, String>(dependingOn: \.self, capacity: 2) { "\($0)" }
    _ = scalar.value(for: 1)
    scalar.removeValue(for: 1)
    scalar.removeAll()
    var combined = ResultCache<(text: String, width: Int), String>(
        dependingOn: \.text,
        \.width,
        capacity: 2
    ) { "\($0.text):\($0.width)" }
    _ = combined.value(for: (text: "Hello", width: 40))
    var local = ResultCache<LocalOwner, LocalOwner>(dependingOn: \.value, capacity: 2) { $0 }
    _ = local.value(for: LocalOwner())
    var nonSendableDependency = ResultCache<LocalValue, Int>(dependingOn: \.self, capacity: 2) {
        $0.value
    }
    _ = nonSendableDependency.value(for: LocalValue(1))
    var constant = ResultCache<LocalOwner, String>(capacity: 1) { _ in "fixed" }
    _ = constant.value(for: LocalOwner())
}

// A non-UI computation can reuse parsing by the source text alone.
func resultCacheTokenization() {
    struct Document {
        struct Content { let text: String }
        let content: Content
        let title: String
    }
    var tokens = ResultCache<Document, [Substring]>(dependingOn: \.content.text, capacity: 4) {
        $0.content.text.split(separator: " ")
    }
    _ = tokens.value(for: Document(content: .init(text: "one two"), title: "Example"))
}
