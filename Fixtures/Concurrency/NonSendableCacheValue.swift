// expected-error: does not conform to the 'Sendable' protocol
func invalid() { requireSendable(MemoizationCache<Int, LocalValue>(capacity: 2)) }
