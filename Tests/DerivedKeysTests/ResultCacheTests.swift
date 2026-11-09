import DerivedKeys
import Testing

@Suite("Result cache")
struct ResultCacheTests {
    @Test
    func selectsMixedNestedValuesAndIgnoresOtherInputs() {
        var cache = ResultCache<Input, Token>(
            dependingOn: \.details.text,
            \.width,
            capacity: 4
        ) { input in Token("\(input.details.text):\(input.width)") }
        let initial = Input(text: "Hello", width: 10, ignored: 1)
        let first = cache.value(for: initial)
        #expect(cache.value(for: Input(text: "Hello", width: 10, ignored: 2)) === first)
        #expect(cache.value(for: Input(text: "Other", width: 10, ignored: 1)) !== first)
        #expect(cache.value(for: Input(text: "Hello", width: 20, ignored: 1)) !== first)
        #expect(first.text == "Hello:10")
        #expect(cache.count == 3)
    }

    @Test
    func namedTupleIncludesWidth() {
        var cache = ResultCache<(text: String, width: Int), Token>(
            dependingOn: \.text,
            \.width,
            capacity: 3
        ) { Token("\($0.text):\($0.width)") }
        let first = cache.value(for: (text: "Hello", width: 10))
        #expect(cache.value(for: (text: "Hello", width: 10)) === first)
        #expect(cache.value(for: (text: "Hello", width: 20)) !== first)
        #expect(cache.count == 2)
    }

    @Test
    func emptySelectionSharesOneResult() {
        var cache = ResultCache<Input, Token>(capacity: 2) { _ in Token("fixed") }
        let first = cache.value(for: Input(text: "One", width: 10, ignored: 1))
        #expect(cache.value(for: Input(text: "Two", width: 20, ignored: 2)) === first)
        #expect(cache.count == 1)
    }

    @Test
    func scalarSelfAndZeroCapacity() {
        var cache = ResultCache<Int, Token>(dependingOn: \.self, capacity: 0) { Token("\($0)") }
        let first = cache.value(for: 1)
        #expect(cache.value(for: 1) !== first)
        #expect(cache.capacity == 0)
        #expect(cache.count == 0)
        cache.removeValue(for: 1)
        cache.removeAll()
        #expect(cache.count == 0)
    }

    @Test
    func collisionsPreserveFullEquality() {
        var cache = ResultCache<CollidingValue, Token>(dependingOn: \.self, capacity: 2) {
            Token("\($0.value)")
        }
        let first = cache.value(for: CollidingValue(value: 1))
        let second = cache.value(for: CollidingValue(value: 2))
        #expect(first !== second)
        #expect(cache.value(for: CollidingValue(value: 1)) === first)
        #expect(cache.value(for: CollidingValue(value: 2)) === second)
    }

    @Test
    func hitsPromoteAndMissesEvictLeastRecent() {
        var cache = ResultCache<Int, Token>(dependingOn: \.self, capacity: 2) { Token("\($0)") }
        let first = cache.value(for: 1)
        let second = cache.value(for: 2)
        #expect(cache.value(for: 1) === first)
        _ = cache.value(for: 3)
        #expect(cache.value(for: 1) === first)
        #expect(cache.value(for: 2) !== second)
        #expect(cache.capacity == 2)
        #expect(cache.count == 2)
    }

    @Test
    func removalUsesSelectedValuesAndClearRetainsConfiguration() {
        var cache = ResultCache<Input, Token>(dependingOn: \.details.text, capacity: 2) {
            Token($0.details.text)
        }
        let input = Input(text: "Hello", width: 1, ignored: 1)
        let first = cache.value(for: input)
        cache.removeValue(for: Input(text: "Missing", width: 2, ignored: 2))
        #expect(cache.count == 1)
        cache.removeValue(for: Input(text: "Hello", width: 2, ignored: 2))
        #expect(cache.count == 0)
        #expect(cache.value(for: input) !== first)
        cache.removeAll()
        #expect(cache.count == 0)
        #expect(cache.capacity == 2)
        #expect(cache.value(for: input).text == "Hello")
    }

    @Test
    func optionalNilIsAHit() async {
        await confirmation(expectedCount: 1) { computed in
            var cache = ResultCache<Int, Int?>(dependingOn: \.self, capacity: 2) { _ in
                computed()
                return nil
            }
            #expect(cache.value(for: 1) == nil)
            #expect(cache.value(for: 1) == nil)
            #expect(cache.count == 1)
        }
    }

    @Test
    func copiesMutateEntriesAndRecencyIndependently() {
        var original = ResultCache<Int, Token>(dependingOn: \.self, capacity: 2) { Token("\($0)") }
        let first = original.value(for: 1)
        let second = original.value(for: 2)
        var copy = original
        #expect(copy.value(for: 1) === first)
        _ = copy.value(for: 3)
        #expect(original.value(for: 2) === second)
        #expect(copy.value(for: 2) !== second)
        original.removeAll()
        #expect(original.count == 0)
        #expect(copy.count == 2)
        copy.removeValue(for: 2)
        #expect(copy.count == 1)
        #expect(original.count == 0)
    }

    @Test
    func entriesDoNotRetainInputsAndProjectedValuesStayStable() {
        var cache = ResultCache<LocalInput, Token>(dependingOn: \.text, capacity: 2) { Token($0.text) }
        var input: LocalInput? = LocalInput(text: "Before")
        weak let weakInput = input
        if let input {
            let first = cache.value(for: input)
            input.text = "After"
            #expect(cache.value(for: input) !== first)
            #expect(cache.value(for: LocalInput(text: "Before")) === first)
        }
        input = nil
        #expect(weakInput == nil)
        #expect(cache.count == 2)
    }

    @Test
    func readsEachSelectedValueOncePerLookupAndRemoval() {
        var cache = ResultCache<ReadCountingInput, Token>(dependingOn: \.selected, capacity: 2) {
            _ in Token("fixed")
        }
        let input = ReadCountingInput()
        let first = cache.value(for: input)
        #expect(input.reads == 1)
        #expect(cache.value(for: input) === first)
        #expect(input.reads == 2)
        cache.removeValue(for: input)
        #expect(input.reads == 3)
        #expect(cache.count == 0)
    }
}

extension ResultCacheTests {
    private struct Input {
        struct Details { let text: String }
        let details: Details
        let width: Int
        let ignored: Int

        init(text: String, width: Int, ignored: Int) {
            details = Details(text: text)
            self.width = width
            self.ignored = ignored
        }
    }

    @MainActor
    private final class IsolatedModel {
        var text = "Hello"
        var width = 10
        var computations = 0
    }

    @MainActor
    @Test
    func mainActorModelKeyPathsAndClosureStayInTheActorRegion() {
        let model = IsolatedModel()
        var cache = ResultCache<IsolatedModel, String>(dependingOn: \.text, \.width, capacity: 2) { input in
            input.computations += 1
            return "\(input.text):\(input.width)"
        }
        #expect(cache.value(for: model) == "Hello:10")
        #expect(cache.value(for: model) == "Hello:10")
        #expect(model.computations == 1)
        model.width = 20
        #expect(cache.value(for: model) == "Hello:20")
        #expect(model.computations == 2)
        model.width = 10
        #expect(cache.value(for: model) == "Hello:10")
        #expect(model.computations == 2)
        #expect(cache.count == 2)
    }

    private final class Token {
        let text: String
        init(_ text: String) { self.text = text }
    }

    private final class LocalInput {
        var text: String
        init(text: String) { self.text = text }
    }

    private final class ReadCountingInput {
        var reads = 0
        var selected: Int {
            reads += 1
            return 1
        }
    }

    private struct CollidingValue: Hashable {
        let value: Int
        func hash(into hasher: inout Hasher) { hasher.combine(0) }
    }
}
