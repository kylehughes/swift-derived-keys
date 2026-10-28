import CoreGraphics
import DerivedKeysUIKit
import Testing

@MainActor
struct LayoutCacheTests {
    private func proposal(width: Double = 120) throws -> FittingProposal {
        FittingProposal(width: try FittingDimension(points: width))
    }

    @Test func completeKeysSeparateInputsProposalsContextsVersionsAndOperations() throws {
        let cache = LayoutCache<Operation, String, Int, Int>(capacity: 4)
        let bounds = try proposal()
        let key = cache.key(for: "Text", proposal: bounds, context: 2)
        #expect(key == cache.key(for: "Text", proposal: bounds, context: 2))
        #expect(key != cache.key(for: "Other", proposal: bounds, context: 2))
        #expect(key != cache.key(for: "Text", proposal: try proposal(width: 121), context: 2))
        let boundedHeight = FittingProposal(width: bounds.width, height: try FittingDimension(points: 40))
        #expect(key != cache.key(for: "Text", proposal: boundedHeight, context: 2))
        #expect(key != cache.key(for: "Text", proposal: bounds, context: 3))
        let versioned = LayoutCache<Operation, String, Int, Int>(capacity: 4, version: 1)
        #expect(key != versioned.key(for: "Text", proposal: bounds, context: 2))
        let otherOperation = LayoutCache<OtherOperation, String, Int, Int>(capacity: 4)
        #expect(AnyHashable(key) != AnyHashable(otherOperation.key(for: "Text", proposal: bounds, context: 2)))
        #expect(cache.count == 0)
        #expect(key.dependencies.input == "Text")
        #expect(key.dependencies.proposal == bounds)
        #expect(key.context == 2)
        #expect(key.version == 0)
    }

    @Test func parentInputsComposeCompleteChildKeys() throws {
        let child = LayoutCache<Operation, String, Int, CGSize>(capacity: 4)
        let parent = LayoutCache<OtherOperation, LayoutKey<Operation, String, Int>?, Int, CGSize>(capacity: 4)
        let narrow = try proposal(width: 100)
        let wide = try proposal(width: 200)
        let narrowChild = child.key(for: "Text", proposal: narrow, context: 2)
        let wideChild = child.key(for: "Text", proposal: wide, context: 2)
        let initial = parent.key(for: narrowChild, proposal: wide, context: 2)
        #expect(initial != parent.key(for: wideChild, proposal: wide, context: 2))
        #expect(initial != parent.key(for: nil, proposal: wide, context: 2))
        #expect(initial.dependencies.input?.dependencies.proposal == narrow)
    }

    @Test func calculationReceivesCapturedValuesAndCachesCompleteGeometry() throws {
        struct Layout: Equatable {
            let size: CGSize
            let frame: CGRect
        }
        let cache = LayoutCache<Operation, String, Int, Layout>(capacity: 4)
        var input = "Original"
        var context = 2
        var bounds = try proposal()
        let capturedKey = cache.key(for: input, proposal: bounds, context: context)
        let expected = Layout(size: CGSize(width: 150, height: 20), frame: CGRect(x: 3, y: 4, width: 140, height: 16))
        let first = cache.value(for: input, proposal: bounds, context: context) {
            suppliedInput,
            proposal,
            suppliedContext in
            input = "Changed"
            context = 3
            bounds = FittingProposal(width: .unconstrained)
            #expect(suppliedInput == capturedKey.dependencies.input)
            #expect(proposal == capturedKey.dependencies.proposal)
            #expect(suppliedContext == capturedKey.context)
            return expected
        }
        #expect(first == expected)
        let second = cache.value(
            for: capturedKey.dependencies.input,
            proposal: capturedKey.dependencies.proposal,
            context: capturedKey.context
        ) { _, _, _ in
            Issue.record("An equal request must reuse the complete layout result")
            return Layout(size: .zero, frame: .zero)
        }
        #expect(second == expected)
        #expect(second.size.width > capturedKey.dependencies.proposal.fittingSize.width)
        #expect(cache.count == 1)
    }

    @Test func aliasesShareStorageAndRecency() throws {
        let cache = LayoutCache<Operation, Int, Int, Int>(capacity: 2)
        let shared = cache
        let bounds = try proposal()
        #expect(cache === shared)
        #expect(cache.capacity == 2)
        #expect(cache.count == 0)
        for input in 1 ... 2 {
            _ = cache.value(for: input, proposal: bounds, context: 0) { input, _, _ in input * 10 }
        }
        #expect(shared.value(for: 1, proposal: bounds, context: 0) { _, _, _ in -1 } == 10)
        _ = shared.value(for: 3, proposal: bounds, context: 0) { _, _, _ in 30 }
        #expect(cache.value(for: 1, proposal: bounds, context: 0) { _, _, _ in -1 } == 10)
        #expect(cache.value(for: 2, proposal: bounds, context: 0) { _, _, _ in 200 } == 200)
        #expect(cache.count == 2)
        shared.removeAll()
        #expect(cache.count == 0)
    }

    @Test func removalUsesTheCompleteKey() throws {
        let cache = LayoutCache<Operation, String, Int, Int>(capacity: 3)
        let narrow = try proposal(width: 100)
        let wide = try proposal(width: 200)
        _ = cache.value(for: "Text", proposal: narrow, context: 0) { _, _, _ in 10 }
        _ = cache.value(for: "Text", proposal: wide, context: 0) { _, _, _ in 20 }
        let narrowKey = cache.key(for: "Text", proposal: narrow, context: 0)
        cache.removeValue(for: narrowKey)
        cache.removeValue(for: narrowKey)
        #expect(cache.count == 1)
        #expect(cache.value(for: "Text", proposal: wide, context: 0) { _, _, _ in -1 } == 20)
        #expect(cache.value(for: "Text", proposal: narrow, context: 0) { _, _, _ in 100 } == 100)
        cache.removeAll()
        cache.removeAll()
        #expect(cache.count == 0)
        #expect(cache.capacity == 3)
    }

    @Test func optionalNilIsAHit() throws {
        let cache = LayoutCache<Operation, Int, Int, CGSize?>(capacity: 1)
        let bounds = try proposal()
        var calculations = 0
        for _ in 0 ..< 2 {
            let value = cache.value(for: 1, proposal: bounds, context: 0) { _, _, _ in
                calculations += 1
                return nil
            }
            #expect(value == nil)
        }
        #expect(calculations == 1)
        #expect(cache.count == 1)
    }

    @Test func failureDoesNotInsertEvictOrPromote() throws {
        let cache = LayoutCache<Operation, Int, Int, Int>(capacity: 2)
        let bounds = try proposal()
        for input in 1 ... 2 {
            _ = cache.value(for: input, proposal: bounds, context: 0) { input, _, _ in input * 10 }
        }
        #expect(throws: CalculationError.failed) {
            try cache.value(for: 3, proposal: bounds, context: 0) { _, _, _ in throw CalculationError.failed }
        }
        #expect(cache.count == 2)
        #expect(throws: Never.self) {
            let value = try cache.value(for: 2, proposal: bounds, context: 0) { _, _, _ in throw CalculationError.failed
            }
            #expect(value == 20)
        }
        _ = cache.value(for: 3, proposal: bounds, context: 0) { _, _, _ in 30 }
        #expect(cache.value(for: 2, proposal: bounds, context: 0) { _, _, _ in -1 } == 20)
        #expect(cache.value(for: 1, proposal: bounds, context: 0) { _, _, _ in 100 } == 100)
    }

    @Test func zeroCapacityAlwaysCalculates() throws {
        let cache = LayoutCache<Operation, Int, Int, Int>(capacity: 0)
        let bounds = try proposal()
        var calculations = 0
        for expected in 1 ... 3 {
            let result = cache.value(for: 1, proposal: bounds, context: 0) { _, _, _ in
                calculations += 1
                return calculations
            }
            #expect(result == expected)
            #expect(cache.count == 0)
        }
    }

    @Test func calculationCaptureIsReleased() throws {
        let cache = LayoutCache<Operation, Int, Int, Int>(capacity: 1)
        let bounds = try proposal()
        var owner: ReferenceValue? = ReferenceValue(value: 42)
        weak let weakOwner = owner
        if let owner {
            _ = cache.value(for: 1, proposal: bounds, context: 0) { _, _, _ in owner.value }
        }
        owner = nil
        #expect(weakOwner == nil)
        #expect(cache.value(for: 1, proposal: bounds, context: 0) { _, _, _ in -1 } == 42)
    }

    @Test func entriesRetainAndReleaseCallerOwnedReferences() throws {
        let cache = LayoutCache<Operation, ReferenceValue, Int, ReferenceValue>(capacity: 1)
        let bounds = try proposal()
        var input: ReferenceValue? = ReferenceValue(value: 1)
        var result: ReferenceValue? = ReferenceValue(value: 2)
        weak let weakInput = input
        weak let weakResult = result
        if let input, let result {
            _ = cache.value(for: input, proposal: bounds, context: 0) { _, _, _ in result }
        }
        input = nil
        result = nil
        #expect(weakInput != nil)
        #expect(weakResult != nil)
        cache.removeAll()
        #expect(weakInput == nil)
        #expect(weakResult == nil)
    }

    @Test func nonSendableInputsContextsAndCallerCapturesStayOnMainActor() throws {
        let cache = LayoutCache<Operation, ReferenceValue, ReferenceValue, ReferenceValue>(capacity: 1)
        let input = ReferenceValue(value: 7)
        let context = ReferenceValue(value: 3)
        let owner = MainActorOwner()
        let bounds = try proposal()
        let value = cache.value(for: input, proposal: bounds, context: context) { suppliedInput, _, suppliedContext in
            owner.calculations += 1
            return ReferenceValue(value: suppliedInput.value + suppliedContext.value)
        }
        #expect(value.value == 10)
        #expect(owner.calculations == 1)
        let again = cache.value(for: input, proposal: bounds, context: context) { _, _, _ in ReferenceValue(value: -1) }
        #expect(again === value)
    }
}

extension LayoutCacheTests {
    private enum Operation {}
    private enum OtherOperation {}
    private enum CalculationError: Error, Equatable {
        case failed
    }

    private final class ReferenceValue: Hashable {
        let value: Int

        init(value: Int) {
            self.value = value
        }

        static func == (lhs: ReferenceValue, rhs: ReferenceValue) -> Bool {
            lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(value)
        }
    }

    @MainActor
    private final class MainActorOwner {
        var calculations = 0
    }
}
