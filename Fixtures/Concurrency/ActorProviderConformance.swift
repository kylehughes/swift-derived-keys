// expected-error: cannot form main actor-isolated conformance
@MainActor struct InvalidProvider: @MainActor KeyValueProvider {
    func value(for input: Int) -> Int { input }
}
