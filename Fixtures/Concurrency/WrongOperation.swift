// expected-error: cannot convert value of type
func invalid() {
    var cache = MemoizationCache<RequestKey<Operation, Int, Int>, Int>(capacity: 2)
    let key = RequestKey<OtherOperation, Int, Int>(dependencies: 1, context: 0)
    _ = cache.value(for: key) { 1 }
}
