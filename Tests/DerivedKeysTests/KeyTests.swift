import DerivedKeys
import Testing

struct KeyTests {
    enum Export {}
    enum Measure {}

    struct Model {
        var text: String
        var selection: Int
    }

    struct Collision: Hashable {
        let value: Int

        func hash(into hasher: inout Hasher) {
            hasher.combine(0)
        }
    }

    final class Owner {
        var reads = 0
        var value = "A"

        func read() -> String {
            reads += 1
            return value
        }
    }

    @Test func projectionTracksRelevantInputsAndRestoresEarlierContent() {
        let projection = KeyProjection(operation: Export.self) { (model: Model) in
            OriginalKey("text", value: model.text)
        }
        var model = Model(text: "A", selection: 0)
        let first = projection.key(for: model, context: "plain")
        var cache = MemoizationCache<RequestKey<Export, OriginalKey<String>, String>, String>(capacity: 3)
        var computations = 0
        func value(_ key: RequestKey<Export, OriginalKey<String>, String>) -> String {
            cache.value(for: key) {
                computations += 1
                return key.dependencies.value
            }
        }
        #expect(value(first) == "A")
        model.selection = 1
        #expect(projection.key(for: model, context: "plain") == first)
        #expect(value(projection.key(for: model, context: "plain")) == "A")
        model.text = "B"
        #expect(value(projection.key(for: model, context: "plain")) == "B")
        model.text = "A"
        #expect(projection.key(for: model, context: "plain") == first)
        #expect(value(projection.key(for: model, context: "plain")) == "A")
        #expect(computations == 2)
    }

    @Test func explicitInputSourcesAndOwnedProjectionsCaptureCurrentValues() {
        let source = KeySource<Model>("text") { $0.text }
        let original = source.snapshot(for: Model(text: "A", selection: 1))
        #expect(source.snapshot(for: Model(text: "A", selection: 2)) == original)
        #expect(source.snapshot(for: Model(text: "B", selection: 1)) != original)

        let owner = Owner()
        let projection = KeyProjection(operation: Export.self) { (_: Void) in owner.read() }
        let first = projection.key(for: (), context: 0)
        owner.value = "B"
        let second = projection.key(for: (), context: 0)
        #expect(first.dependencies == "A")
        #expect(second.dependencies == "B")
    }

    @Test func operationAndVersionArePartOfTheRequest() {
        let export = RequestKey(operation: Export.self, dependencies: 1, context: "same")
        let measure = RequestKey(operation: Measure.self, dependencies: 1, context: "same")
        let newer = RequestKey(operation: Export.self, version: 1, dependencies: 1, context: "same")
        #expect(AnyHashable(export) != AnyHashable(measure))
        #expect(export != newer)
        var cache = MemoizationCache<AnyHashable, String>(capacity: 3)
        #expect(cache.value(for: AnyHashable(export)) { "export" } == "export")
        #expect(cache.value(for: AnyHashable(measure)) { "measure" } == "measure")
    }

    @Test func collisionsRetainCompleteKeysAtEveryLevel() throws {
        let first = KeySource<Void>("value", value: Collision(value: 1))
        let second = KeySource<Void>("value", value: Collision(value: 2))
        let nestedFirst = try KeySource<Void>("nested", children: [first])
        let nestedSecond = try KeySource<Void>("nested", children: [second])
        let roots = try [nestedFirst, nestedSecond].map { try KeySource<Void>("root", children: [$0]) }
        for pair in [(first, second), (nestedFirst, nestedSecond), (roots[0], roots[1])] {
            let a = pair.0.snapshot(for: ())
            let b = pair.1.snapshot(for: ())
            #expect(a != b)
            var cache = MemoizationCache<DependencySnapshot, Int>(capacity: 2)
            #expect(cache.value(for: a) { 1 } == 1)
            #expect(cache.value(for: b) { 2 } == 2)
            #expect(cache.value(for: a) { 99 } == 1)
        }
    }

    @Test func concreteValueTypesAndNodeKindsRemainDistinct() throws {
        let integer = KeySource<Void>("value", value: Int(1)).snapshot(for: ())
        let smallInteger = KeySource<Void>("value", value: Int8(1)).snapshot(for: ())
        let optional = KeySource<Void>("value", value: Optional(1)).snapshot(for: ())
        let originalArray = KeySource<Void>("value", value: [Int]()).snapshot(for: ())
        let derived = try KeySource<Void>("value", children: []).snapshot(for: ())
        #expect(integer != smallInteger)
        #expect(integer != optional)
        #expect(originalArray != derived)
        #expect(AnyHashable(OriginalKey("value", value: 1)) != AnyHashable(DerivedKey("value", children: 1)))
    }

    @Test func structurePreservesOrderMultiplicityAbsenceAndBoundaries() throws {
        let a = KeySource<Void>("a", value: 1)
        let b = KeySource<Void>("b", value: 2)
        let ordered = try KeySource<Void>("root", children: [a, b])
        let reversed = try KeySource<Void>("root", children: [b, a])
        let repeated = try KeySource<Void>("root", children: [a, b, b])
        let absent = try KeySource<Void>("root", children: [a])
        let nested = try KeySource<Void>("root", children: [KeySource("child", children: [a, b])])
        let variants = [ordered, reversed, repeated, absent, nested].map { $0.snapshot(for: ()) }
        #expect(Set(variants).count == variants.count)
        #expect(
            KeySource<Void>("value", value: [1, 2]).snapshot(for: ())
                != KeySource<Void>("value", value: [2, 1]).snapshot(for: ())
        )
        #expect(
            KeySource<Void>("value", value: Set([1, 2])).snapshot(for: ())
                == KeySource<Void>("value", value: Set([2, 1])).snapshot(for: ())
        )
        #expect(
            KeySource<Void>("value", value: Int?.none).snapshot(for: ())
                != KeySource<Void>("value", value: Int?.some(0)).snapshot(for: ())
        )
    }

    @Test func appendingAndRebindingDoNotChangeExistingGraphs() throws {
        var child = KeySource<Void>("child", value: 1)
        let original = try KeySource<Void>("root", children: [child])
        let captured = original.snapshot(for: ())
        child = KeySource("child", value: 2)
        let extended = try original.appending(child)
        #expect(original.snapshot(for: ()) == captured)
        #expect(extended.snapshot(for: ()) != captured)
        #expect(throws: KeySource<Void>.ConstructionError.notDerived) {
            try child.appending(original)
        }
    }

    @Test func independentEqualSchemasProduceEqualKeys() throws {
        let a = try KeySource<Void>("root", children: [KeySource("text", value: "Hello")])
        let b = try KeySource<Void>("root", children: [KeySource("text", value: "Hello")])
        let first = a.snapshot(for: ())
        let second = b.snapshot(for: ())
        #expect(first == second)
        #expect(Set([first, second]).count == 1)
        #expect(
            try KeySource<Void>("empty", children: []).snapshot(for: ())
                == KeySource<Void>("empty", children: []).snapshot(for: ())
        )
        #expect(
            try KeySource<Void>("a", children: []).snapshot(for: ())
                != KeySource<Void>("b", children: []).snapshot(for: ())
        )
    }

    @Test func sharedProviderIsReadOncePerEvaluationAndSnapshotsStayStable() throws {
        let owner = Owner()
        let shared = KeySource<Void>("text", provider: { owner.read() })
        let graph = try KeySource<Void>("root", children: [shared, KeySource("nested", children: [shared])])
        let first = graph.snapshot(for: ())
        #expect(owner.reads == 1)
        owner.value = "B"
        let second = graph.snapshot(for: ())
        #expect(owner.reads == 2)
        #expect(first != second)
        owner.value = "A"
        #expect(graph.snapshot(for: ()) == first)
        #expect(owner.reads == 3)
    }

    @Test func evaluatedKeysDoNotRetainProvidersOrTheirOwners() {
        weak var reference: Owner?
        var retained: DependencySnapshot?
        do {
            let owner = Owner()
            reference = owner
            let source = KeySource<Void>("text", provider: { owner.read() })
            retained = source.snapshot(for: ())
        }
        #expect(reference == nil)
        #expect(retained == KeySource<Void>("text", value: "A").snapshot(for: ()))
    }

    @Test func supportedDepthHasACheckedBoundary() throws {
        var source = KeySource<Void>("leaf", value: 1)
        for _ in 1 ..< KeySource<Void>.maximumDepth {
            source = try KeySource("parent", children: [source])
        }
        #expect(source.snapshot(for: ()) == source.snapshot(for: ()))
        #expect(throws: KeySource<Void>.ConstructionError.maximumDepthExceeded) {
            try KeySource("overflow", children: [source])
        }
    }

    @Test func typedCompositionAndContextDistinguishInputs() {
        let a = DerivedKey("root", children: KeyPair(OriginalKey("a", value: 1), OriginalKey("b", value: "two")))
        let b = DerivedKey("root", children: KeyPair(OriginalKey("a", value: 2), OriginalKey("b", value: "two")))
        let first = RequestKey(operation: Measure.self, dependencies: a, context: 100)
        let wider = RequestKey(operation: Measure.self, dependencies: a, context: 200)
        let changed = RequestKey(operation: Measure.self, dependencies: b, context: 100)
        #expect(first != wider)
        #expect(first != changed)
    }
}
