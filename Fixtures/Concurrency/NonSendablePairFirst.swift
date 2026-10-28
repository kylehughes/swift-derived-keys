// expected-error: does not conform to the 'Sendable' protocol
func invalid() { requireSendable(KeyPair(LocalValue(1), 1)) }
