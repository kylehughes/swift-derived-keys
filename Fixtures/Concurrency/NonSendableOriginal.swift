// expected-error: does not conform to the 'Sendable' protocol
func invalid() { requireSendable(OriginalKey("value", value: LocalValue(1))) }
