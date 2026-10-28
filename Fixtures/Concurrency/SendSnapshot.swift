// expected-error: risks causing data races
actor Receiver {
    func consume(_ snapshot: DependencySnapshot) {}
}

@MainActor func invalid(receiver: Receiver) async {
    let snapshot = KeySource<Int>("number", provider: { $0 }).snapshot(for: 1)
    await receiver.consume(snapshot)
    _ = snapshot.hashValue
}
