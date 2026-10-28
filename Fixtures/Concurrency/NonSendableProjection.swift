// expected-error: does not conform to the 'Sendable' protocol
func invalid() { requireSendable(KeyProjection(operation: Operation.self) { (input: Int) in input }) }
