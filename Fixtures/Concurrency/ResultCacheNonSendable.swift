// expected-error: does not conform to the 'Sendable' protocol
func invalidResultCacheTransfer() {
    requireSendable(ResultCache<Int, Int>(dependingOn: \.self, capacity: 1) { $0 })
}
