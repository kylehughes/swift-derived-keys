// expected-error: main actor-isolated property 'count'
@MainActor final class Model {
    var count = 1
}

struct InvalidProvider: KeyValueProvider {
    let model: Model

    func value(for input: Int) -> Int { model.count + input }
}
