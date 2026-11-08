// expected-error: cannot convert value of type 'String' to expected argument type 'Int'
func invalidResultCacheInput() {
    var cache = ResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { $0 }
    _ = cache.value(for: "wrong")
}
