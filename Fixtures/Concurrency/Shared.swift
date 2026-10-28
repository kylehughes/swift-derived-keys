import DerivedKeys

// Operation tokens deliberately need no Sendable conformance.
final class Operation {}
enum OtherOperation {}

final class LocalValue: Hashable {
    let value: Int

    init(_ value: Int) { self.value = value }

    static func == (lhs: LocalValue, rhs: LocalValue) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

func requireSendable<T: Sendable>(_ value: T) {}

final class LocalOwner {
    var value = 1
}

struct LocalLiveProvider: KeyValueProvider {
    let owner: LocalOwner

    func value(for input: Int) -> Int {
        owner.value + input
    }
}

struct LocalValueProvider: KeyValueProvider {
    func value(for input: LocalValue) -> LocalValue { input }
}

struct LocalInputProvider: KeyValueProvider {
    func value(for input: LocalOwner) -> Int { input.value }
}
