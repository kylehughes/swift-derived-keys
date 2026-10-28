// expected-error: does not conform to the 'Sendable' protocol
func invalid() { requireSendable(MemoizationCache<LocalValue, Int>(capacity: 2)) }
