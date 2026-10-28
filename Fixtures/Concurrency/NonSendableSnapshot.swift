// expected-error: does not conform to the 'Sendable' protocol
func invalid() { requireSendable(KeySource<Int>("number", provider: { $0 }).snapshot(for: 1)) }
