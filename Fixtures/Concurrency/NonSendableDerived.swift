// expected-error: does not conform to the 'Sendable' protocol
func invalid() { requireSendable(DerivedKey("value", children: LocalValue(1))) }
