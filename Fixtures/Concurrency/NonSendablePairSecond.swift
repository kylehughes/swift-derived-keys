// expected-error: does not conform to the 'Sendable' protocol
func invalid() { requireSendable(KeyPair(1, LocalValue(1))) }
