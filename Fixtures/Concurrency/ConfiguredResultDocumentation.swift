import DerivedKeys

// Mirrors the complete scalar example in Examples/Result-Caches.md.
func resultCacheGuideExample() {
    var tokens = ResultCache<String, [String]>(dependingOn: \.self, capacity: 128) { text in
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }
    let words = tokens.value(for: "Cached search tokens")
    assert(words == ["Cached", "search", "tokens"])
}
