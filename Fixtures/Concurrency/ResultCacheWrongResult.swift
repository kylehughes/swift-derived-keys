// expected-error: cannot convert value of type 'String' to closure result type 'Int'
func invalidResultCacheResult() {
    _ = ResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { _ in "wrong" }
}
