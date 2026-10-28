// expected-error: does not conform to the 'Sendable' protocol
func invalid() {
    requireSendable(RequestKey<Operation, LocalValue, Int>(dependencies: LocalValue(1), context: 0))
}
