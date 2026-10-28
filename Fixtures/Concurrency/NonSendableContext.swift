// expected-error: does not conform to the 'Sendable' protocol
func invalid() {
    requireSendable(RequestKey<Operation, Int, LocalValue>(dependencies: 1, context: LocalValue(0)))
}
