import DerivedKeysUI
import Testing

@MainActor
struct MainActorResultCacheTests {
    @Test func heterogeneousNestedSelectionsIgnoreUnselectedChangesAndInputIdentity() {
        var calls = 0
        let cache = MainActorResultCache<ResultInput, String>(
            dependingOn: \.name,
            \.child.value,
            \.enabled,
            capacity: 8
        ) { input in
            calls += 1
            return "\(input.name):\(input.child.value):\(input.enabled)"
        }
        let input = ResultInput(2)
        #expect(cache.value(for: input) == "name:2:true")
        #expect(cache.value(for: ResultInput(2)) == "name:2:true")
        input.unselected += 1
        #expect(cache.value(for: input) == "name:2:true")
        #expect(calls == 1)
        input.child.value = 3
        #expect(cache.value(for: input) == "name:3:true")
        input.name = "other"
        #expect(cache.value(for: input) == "other:3:true")
        input.enabled = false
        #expect(cache.value(for: input) == "other:3:false")
        #expect(calls == 4)
    }

    @Test func capturesEachProjectionOncePerLookupAndRemoval() {
        var calls = 0
        let cache = MainActorResultCache<ResultInput, Int>(dependingOn: \.projection, capacity: 4) { input in
            calls += 1
            return input.child.value
        }
        let input = ResultInput(1)
        #expect(cache.value(for: input) == 1)
        #expect(cache.value(for: input) == 1)
        #expect(input.reads == 2)
        input.child.value = 2
        #expect(cache.value(for: input) == 2)
        cache.removeValue(for: input)
        #expect(input.reads == 4)
        #expect(cache.count == 1)
        input.child.value = 1
        #expect(cache.value(for: input) == 1)
        #expect(calls == 2)
    }

    @Test func emptySelectionAndExplicitWholeInputHaveDifferentPolicies() {
        var emptyCalls = 0
        let empty = MainActorResultCache<Int, Int>(capacity: 2) { input in
            emptyCalls += 1
            return input
        }
        #expect(empty.value(for: 1) == 1)
        #expect(empty.value(for: 2) == 1)
        #expect(emptyCalls == 1)
        let whole = MainActorResultCache<Int, Int>(dependingOn: \.self, capacity: 2) { $0 * 2 }
        #expect(whole.value(for: 1) == 2)
        #expect(whole.value(for: 2) == 4)
        #expect(whole.count == 2)
    }

    @Test func namedTupleParametersAndExplicitStagesReuseIndependently() {
        typealias Request = (content: ResultInput, width: Int)
        var contentCalls = 0
        var layoutCalls = 0
        let content = MainActorResultCache<ResultInput, Int>(dependingOn: \.child.value, capacity: 4) { input in
            contentCalls += 1
            return input.child.value * 2
        }
        let layout = MainActorResultCache<Request, Int>(
            dependingOn: \.content.child.value,
            \.width,
            capacity: 4
        ) { request in
            layoutCalls += 1
            return content.value(for: request.content) + request.width
        }
        let input = ResultInput(2)
        #expect(layout.value(for: (input, 10)) == 14)
        #expect(layout.value(for: (input, 10)) == 14)
        #expect(layout.value(for: (input, 20)) == 24)
        #expect(contentCalls == 1)
        #expect(layoutCalls == 2)
        input.child.value = 3
        #expect(layout.value(for: (input, 20)) == 26)
        #expect(contentCalls == 2)
        #expect(layoutCalls == 3)
    }

    @Test func fullValueEqualityDistinguishesHashCollisions() {
        var calls = 0
        let cache = MainActorResultCache<ResultCollision, Int>(dependingOn: \.self, capacity: 4) { input in
            calls += 1
            return input.value
        }
        #expect(cache.value(for: ResultCollision(value: 1)) == 1)
        #expect(cache.value(for: ResultCollision(value: 2)) == 2)
        #expect(cache.value(for: ResultCollision(value: 1)) == 1)
        #expect(calls == 2)
    }

    @Test func optionalNilIsAHitAndZeroCapacityAlwaysCalculates() {
        var calls = 0
        let optional = MainActorResultCache<Int, Int?>(dependingOn: \.self, capacity: 1) { _ in
            calls += 1
            return nil
        }
        #expect(optional.value(for: 1) == nil)
        #expect(optional.value(for: 1) == nil)
        #expect(calls == 1)
        #expect(optional.count == 1)
        let disabled = MainActorResultCache<Int, Int>(capacity: 0) { input in
            calls += 1
            return input
        }
        #expect(disabled.value(for: 1) == 1)
        #expect(disabled.value(for: 2) == 2)
        #expect(calls == 3)
        #expect(disabled.capacity == 0)
        #expect(disabled.count == 0)
    }

    @Test func aliasesShareLRUOrderWhileIndependentRecipesKeepSeparateStorage() {
        var calls = 0
        let cache = MainActorResultCache<Int, Int>(dependingOn: \.self, capacity: 2) { input in
            calls += 1
            return input
        }
        let alias = cache
        #expect(cache.value(for: 1) == 1)
        #expect(cache.value(for: 2) == 2)
        #expect(alias.value(for: 1) == 1)
        #expect(alias.value(for: 3) == 3)
        #expect(cache.value(for: 1) == 1)
        #expect(calls == 3)
        #expect(cache.value(for: 2) == 2)
        #expect(calls == 4)
        #expect(cache.count == 2)
        #expect(cache.capacity == 2)
        let independent = MainActorResultCache<Int, Int>(dependingOn: \.self, capacity: 2) { $0 * 10 }
        #expect(independent.value(for: 2) == 20)
        alias.removeValue(for: 2)
        #expect(cache.count == 1)
        #expect(independent.count == 1)
        alias.removeAll()
        #expect(cache.count == 0)
        #expect(independent.count == 1)
    }

    @Test func entriesDoNotImplicitlyRetainInputsOrRequireSendableResults() {
        let cache = MainActorResultCache<ResultInput, ResultObject>(dependingOn: \.child.value, capacity: 1) {
            ResultObject($0.child.value)
        }
        weak var inputReference: ResultInput?
        do {
            let input = ResultInput(7)
            inputReference = input
            let result = cache.value(for: input)
            #expect(result.value == 7)
            #expect(cache.value(for: ResultInput(7)) === result)
        }
        #expect(inputReference == nil)
        #expect(cache.count == 1)
    }

    @Test func configuredCalculationRetainsExplicitCapturesUntilCacheRelease() {
        var object: ResultObject? = ResultObject(9)
        weak let reference = object
        var cache: MainActorResultCache<Int, Int>? = MainActorResultCache(capacity: 1) { [object] _ in
            object?.value ?? 0
        }
        object = nil
        #expect(reference != nil)
        #expect(cache?.value(for: 1) == 9)
        cache = nil
        #expect(reference == nil)
    }
}

private final class ResultInput {
    var name = "name"
    var enabled = true
    var unselected = 0
    var reads = 0
    let child: ResultObject
    var projection: Int {
        reads += 1
        return child.value
    }
    init(_ value: Int) { child = ResultObject(value) }
}

private final class ResultObject {
    var value: Int
    init(_ value: Int) { self.value = value }
}

private struct ResultCollision: Hashable {
    let value: Int
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
}
