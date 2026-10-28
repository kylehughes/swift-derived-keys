func typedTransfers() {
    let original = OriginalKey("number", value: 1)
    let pair = KeyPair(original, "context")
    let derived = DerivedKey("result", children: pair)
    let request = RequestKey<Operation, Int, String>(dependencies: 1, context: "en")
    requireSendable(original)
    requireSendable(pair)
    requireSendable(derived)
    requireSendable(request)
    requireSendable(MemoizationCache<RequestKey<Operation, Int, String>, Int>(capacity: 2))
}

func confinedNonSendableValues() {
    let local = LocalValue(1)
    let original = OriginalKey("local", value: local)
    let pair = KeyPair(original, local)
    let derived = DerivedKey("local", children: pair)
    let request = RequestKey<Operation, LocalValue, LocalValue>(dependencies: local, context: local)
    var cache = MemoizationCache<RequestKey<Operation, LocalValue, LocalValue>, LocalValue>(capacity: 2)
    _ = cache.value(for: request) { local }
    let source = KeySource<LocalValue>("local", provider: LocalValueProvider())
    let snapshot = source.snapshot(for: local)
    _ = [snapshot: derived]
    let projection = KeyProjection(operation: Operation.self) { (input: LocalValue) in input }
    _ = projection.key(for: local, context: local)
}

@MainActor final class Model {
    var count = 1

    func capturedInput() {
        let captured = count
        let source = KeySource<Int>("count", provider: { $0 })
        _ = source.snapshot(for: captured)
        let projection = KeyProjection(operation: Operation.self) { (input: Int) in input }
        requireSendable(projection.key(for: captured, context: "en"))
    }
}

actor Receiver {
    func consume(_ key: RequestKey<Operation, Int, String>) {}
}

@MainActor func transferTypedKey(receiver: Receiver) async {
    let key = RequestKey<Operation, Int, String>(dependencies: 1, context: "en")
    await receiver.consume(key)
    _ = key.hashValue
}

func confinedLiveProvider() {
    let owner = LocalOwner()
    let provider = LocalLiveProvider(owner: owner)
    let source = KeySource<Int>("live", provider: provider)
    let projection = KeyProjection(operation: Operation.self, provider: provider)
    owner.value = 2
    _ = source.snapshot(for: 1)
    _ = projection.key(for: 1, context: "en")
    _ = KeySource<LocalOwner>("nonhashable-input", provider: LocalInputProvider()).snapshot(for: owner)
    let valueProjection = KeyProjection(operation: Operation.self, provider: LocalValueProvider())
    _ = valueProjection.key(for: LocalValue(1), context: "en")
}
