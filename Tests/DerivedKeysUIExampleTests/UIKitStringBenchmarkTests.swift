#if canImport(UIKit)
import DerivedKeys
import DerivedKeysUI
import Dispatch
import UIKit
import XCTest

final class UIKitStringBenchmarkTests: XCTestCase {
    @MainActor
    func testStringRepresentationBenchmarks() throws {
        let options = try StringBenchmarkOptions()
        var rows: [StringBenchmarkRow] = []
        var costs: [StringCostRow] = []
        var representations: [StringRepresentation] = []
        for content in StringContent.allCases {
            let inputs = content.inputs()
            for strategy in StringStrategy.cached {
                // Observe public representation before warmup, UTF-8 traversal, equality, or hashing.
                let sourceContiguous = inputs[0].isContiguousUTF8
                let fixture = StringFixture(strategy: strategy, text: inputs[0], warmed: false)
                let rawUIKit = fixture.root.textView.text ?? ""
                let rawContiguous = rawUIKit.isContiguousUTF8
                let value = fixture.readText()
                let contiguous = value.isContiguousUTF8
                XCTAssertEqual(value, inputs[0])
                representations.append(
                    StringRepresentation(
                        content: content.rawValue,
                        strategy: strategy.rawValue,
                        utf8Length: inputs[0].utf8.count,
                        isContiguousUTF8: contiguous,
                        rawUIKitIsContiguousUTF8: rawContiguous,
                        sourceIsContiguousUTF8: sourceContiguous
                    )
                )
                costs += StringFixture(strategy: strategy, text: inputs[0])
                    .costs(
                        content: content,
                        iterations: options.phaseIterations,
                        trials: options.phaseTrials
                    )
            }
            for scenario in StringScenario.allCases {
                let requests = scenario.requests(count: options.iterations)
                var trials = Array(repeating: [StringTrial](), count: StringStrategy.allCases.count)
                for trial in 0 ..< options.trials {
                    // All allocation, native input generation, and warmup precede each timed arm.
                    let fixtures = StringStrategy.allCases.map { StringFixture(strategy: $0, text: inputs[0]) }
                    var results = StringStrategy.allCases.map { _ in
                        Array(repeating: CGSize.zero, count: requests.count)
                    }
                    var elapsed = Array(repeating: UInt64(0), count: fixtures.count)
                    for offset in 0 ..< fixtures.count {
                        let arm = (trial + offset) % fixtures.count
                        elapsed[arm] = fixtures[arm]
                            .run(
                                requests,
                                inputs: inputs,
                                scenario: scenario,
                                results: &results[arm]
                            )
                    }
                    let expected = results[0]
                    XCTAssertTrue(
                        expected.allSatisfy { $0.width.isFinite && $0.width > 0 && $0.height.isFinite && $0.height > 0 }
                    )
                    if scenario != .repeatedWarm { XCTAssertGreaterThan(Set(expected.map(\.height)).count, 1) }
                    for arm in fixtures.indices {
                        XCTAssertEqual(results[arm], expected, "\(content.rawValue)/\(scenario.rawValue)/\(arm)")
                        XCTAssertLessThanOrEqual(fixtures[arm].cache.count, StringFixture.capacity)
                        trials[arm]
                            .append(
                                StringTrial(
                                    index: trial,
                                    orderIndex: (arm - trial % fixtures.count + fixtures.count) % fixtures.count,
                                    elapsedNanoseconds: elapsed[arm],
                                    nanosecondsPerOperation: Double(elapsed[arm]) / Double(requests.count),
                                    checksum: Self.checksum(results[arm]),
                                    expectedChecksum: Self.checksum(expected),
                                    resultsValidated: results[arm] == expected
                                )
                            )
                    }
                }
                for (arm, strategy) in StringStrategy.allCases.enumerated() {
                    let diagnostic = StringFixture(strategy: strategy, text: inputs[0], counted: true)
                        .diagnose(
                            scenario.requests(count: max(128, options.iterations)),
                            inputs: inputs,
                            scenario: scenario
                        )
                    rows.append(
                        StringBenchmarkRow(
                            content: content.rawValue,
                            scenario: scenario.rawValue,
                            strategy: strategy.rawValue,
                            timingBoundary: scenario.timingBoundary,
                            iterations: options.iterations,
                            capacity: StringFixture.capacity,
                            trials: trials[arm],
                            diagnostics: diagnostic,
                            resultsValidated: trials[arm].allSatisfy(\.resultsValidated) && diagnostic.resultsValidated
                        )
                    )
                }
            }
        }
        let report = StringBenchmarkReport(
            schemaVersion: 1,
            benchmarkEnabled: options.enabled,
            iterations: options.iterations,
            trials: options.trials,
            capacity: StringFixture.capacity,
            phaseIterations: options.phaseIterations,
            phaseTrials: options.phaseTrials,
            runtime: StringRuntime(),
            rows: rows,
            costDiagnostics: costs,
            representations: representations,
            warmupIterationsPerView: StringFixture.warmupIterations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "DerivedKeysUIKitStringBenchmarks.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func checksum(_ sizes: [CGSize]) -> Double {
        sizes.reduce(0) { $0 + Double($1.width + $1.height) }
    }
}

private struct StringBenchmarkOptions {
    let enabled: Bool
    let iterations: Int
    let trials: Int
    var phaseIterations: Int { enabled ? 512 : 8 }
    var phaseTrials: Int { enabled ? 5 : 1 }

    init() throws {
        let environment = ProcessInfo.processInfo.environment
        enabled = environment["DERIVEDKEYS_UIKIT_BENCHMARK"] == "1"
        iterations = try Self.integer(
            environment["DERIVEDKEYS_UIKIT_ITERATIONS"],
            fallback: enabled ? 128 : 8,
            range: 8 ... 512
        )
        trials = try Self.integer(environment["DERIVEDKEYS_UIKIT_TRIALS"], fallback: enabled ? 9 : 1, range: 1 ... 31)
        #if DEBUG
        if enabled { throw ConfigurationError.releaseRequired }
        #endif
    }

    private static func integer(_ value: String?, fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value else { return fallback }
        guard let parsed = Int(value), range.contains(parsed) else { throw ConfigurationError.invalidInteger }
        return parsed
    }

    private enum ConfigurationError: Error { case invalidInteger, releaseRequired }
}

private enum StringContent: String, CaseIterable {
    case shortASCII = "short-ascii"
    case longASCII = "long-ascii"
    case longNonASCII = "long-non-ascii"

    func inputs() -> [String] {
        let base: String
        switch self {
        case .shortASCII: base = "Short native title."
        case .longASCII:
            base = String(repeating: "Long text includes punctuation, dates, and several measured lines. ", count: 24)
        case .longNonASCII: base = String(repeating: "Café résumé 日本語 中文 👩🏽‍💻 🌍. ", count: 32)
        }
        // Ordinary native Swift construction; the model arm never repairs storage representation.
        return (0 ..< 40)
            .map { index in
                base + " Variant \(index)." + String(repeating: " Extra wrapping content.", count: index % 8 * 4)
            }
    }
}

private enum StringStrategy: String, CaseIterable {
    case direct
    case uiKitText = "uikit-text"
    case modelText = "model-text"
    case contiguousUIKitText = "contiguous-uikit-text"
    static var cached: [Self] { [.uiKitText, .modelText, .contiguousUIKitText] }
}

private enum StringScenario: String, CaseIterable {
    case repeatedWarm = "repeated-warm"
    case mutationReturn = "mutation-return"
    case mixedBounded = "mixed-bounded"

    func requests(count: Int) -> [Int] {
        (0 ..< count)
            .map { index in
                switch self {
                case .repeatedWarm: 0
                case .mutationReturn: [0, 1, 0, 2, 0, 3, 0, 4][index % 8]
                case .mixedBounded: (index / 2) % 40
                }
            }
    }

    var timingBoundary: String {
        let configuration =
            self == .repeatedWarm
            ? "No configuration in loop; " : "Identical model.text and UITextView.text setters before every request; "
        return configuration
            + "complete direct fit or SizeCache.size including dependency reads, per-request normalization where selected, snapshot, hashing, equality, lookup/miss fit, and preallocated CGSize-buffer write"
    }
}

@MainActor
private final class StringRoot {
    struct Model { var text: String }
    var model: Model
    let textView = UITextView()
    var contiguousUIKitText: String {
        var text = textView.text ?? ""
        text.makeContiguousUTF8()
        return text
    }

    init(text: String) {
        model = Model(text: text)
        textView.font = UIFont.systemFont(ofSize: 17)
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.semanticContentAttribute = .forceLeftToRight
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        configure(text)
    }

    func configure(_ text: String) {
        model.text = text
        textView.text = text
    }
}

@MainActor
private final class StringFixture {
    static let capacity = 16
    static let warmupIterations = 8
    static let proposal = CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
    let root: StringRoot
    let strategy: StringStrategy
    let cache: SizeCache<StringRoot>
    private let counter: StringMeasurementCounter

    init(strategy: StringStrategy, text: String, counted: Bool = false, warmed: Bool = true) {
        self.strategy = strategy
        root = StringRoot(text: text)
        let counter = StringMeasurementCounter()
        self.counter = counter
        let measure: @MainActor (StringRoot, CGSize) -> CGSize
        if counted {
            measure = { root, proposal in
                counter.measurements += 1
                return root.textView.sizeThatFits(proposal)
            }
        } else {
            measure = { root, proposal in root.textView.sizeThatFits(proposal) }
        }
        switch strategy {
        case .direct, .uiKitText:
            cache = SizeCache(dependingOn: \.textView.text, \.textView.font, capacity: Self.capacity, measure: measure)
        case .modelText:
            cache = SizeCache(dependingOn: \.model.text, \.textView.font, capacity: Self.capacity, measure: measure)
        case .contiguousUIKitText:
            cache = SizeCache(
                dependingOn: \.contiguousUIKitText,
                \.textView.font,
                capacity: Self.capacity,
                measure: measure
            )
        }
        if warmed {
            for _ in 0 ..< (Self.warmupIterations - 1) { _ = root.textView.sizeThatFits(Self.proposal) }
            if strategy == .direct {
                _ = root.textView.sizeThatFits(Self.proposal)
            } else {
                _ = cache.size(of: root, toFit: Self.proposal)
            }
        }
        counter.measurements = 0
    }

    func readText() -> String {
        switch strategy {
        case .direct, .uiKitText: root.textView.text ?? ""
        case .modelText: root.model.text
        case .contiguousUIKitText: root.contiguousUIKitText
        }
    }

    func run(_ requests: [Int], inputs: [String], scenario: StringScenario, results: inout [CGSize]) -> UInt64 {
        results.withUnsafeMutableBufferPointer { buffer in
            let start = DispatchTime.now().uptimeNanoseconds
            for operation in requests.indices {
                if scenario != .repeatedWarm { root.configure(inputs[requests[operation]]) }
                buffer[operation] =
                    strategy == .direct
                    ? root.textView.sizeThatFits(Self.proposal) : cache.size(of: root, toFit: Self.proposal)
            }
            return DispatchTime.now().uptimeNanoseconds - start
        }
    }

    func diagnose(_ requests: [Int], inputs: [String], scenario: StringScenario) -> StringDiagnostics {
        var hits = 0
        var misses = 0
        var valid = true
        var sizes: [CGSize] = []
        var returnHit = false
        var expectedRecency = [0]
        for (index, request) in requests.enumerated() {
            if scenario != .repeatedWarm { root.configure(inputs[request]) }
            XCTAssertEqual(root.model.text, root.textView.text)
            let before = counter.measurements
            let result =
                strategy == .direct
                ? root.textView.sizeThatFits(Self.proposal) : cache.size(of: root, toFit: Self.proposal)
            let expected = root.textView.sizeThatFits(Self.proposal)
            valid = valid && result == expected
            sizes.append(result)
            if strategy != .direct {
                let hit = counter.measurements == before
                let expectedIndex = expectedRecency.firstIndex(of: request)
                let expectedHit = expectedIndex != nil
                if let expectedIndex { expectedRecency.remove(at: expectedIndex) }
                expectedRecency.append(request)
                if expectedRecency.count > Self.capacity { expectedRecency.removeFirst() }
                XCTAssertEqual(hit, expectedHit, "Untimed independent integer-identity LRU replay")
                XCTAssertEqual(cache.count, expectedRecency.count)
                valid = valid && hit == expectedHit && cache.count == expectedRecency.count
                if hit { hits += 1 } else { misses += 1 }
                if scenario == .mutationReturn && index == 2 {
                    returnHit = hit && result == sizes[0] && result != sizes[1]
                }
            }
        }
        let different = Set(sizes.map(\.height)).count > 1
        let restored = scenario == .repeatedWarm || (sizes[0] == sizes[2] && sizes[0] != sizes[1])
        let eviction = strategy != .direct && misses > cache.count && cache.count == Self.capacity
        XCTAssertTrue(valid)
        if scenario != .repeatedWarm { XCTAssertTrue(different) }
        if scenario == .mutationReturn {
            XCTAssertTrue(restored)
            if strategy != .direct { XCTAssertTrue(returnHit) }
        }
        if scenario == .mixedBounded && strategy != .direct { XCTAssertTrue(eviction) }
        XCTAssertLessThanOrEqual(cache.count, Self.capacity)
        return StringDiagnostics(
            iterations: requests.count,
            hits: hits,
            misses: misses,
            measurementCount: strategy == .direct ? requests.count : counter.measurements,
            entryCount: cache.count,
            evictionObserved: eviction,
            returnHitValidated: returnHit,
            distinctHeightsObserved: different,
            restoredResultValidated: scenario == .mutationReturn && restored,
            resultsValidated: valid
        )
    }

    func costs(content: StringContent, iterations: Int, trials: Int) -> [StringCostRow] {
        let first = cache.snapshot(of: root)
        // Read each slot outside the hash phase; no normalization or getter is hidden in that phase.
        let preRead = (0 ..< 64).map { _ in readText() }
        let preconstructed = (0 ..< 64).map { _ in cache.snapshot(of: root) }
        var rows: [StringCostRow] = []
        for phase in StringCostPhase.allCases {
            var samples: [StringCostTrial] = []
            for trial in 0 ..< trials {
                var texts = preRead
                var snapshots = preconstructed
                var hashSum: UInt64 = 0
                let elapsed: UInt64
                let checksum: String
                let expected: String
                let valid: Bool
                switch phase {
                case .dependencyRead:
                    elapsed = texts.withUnsafeMutableBufferPointer { buffer in
                        let start = DispatchTime.now().uptimeNanoseconds
                        for operation in 0 ..< iterations { buffer[operation % 64] = readText() }
                        return DispatchTime.now().uptimeNanoseconds - start
                    }
                    valid = texts.allSatisfy { $0 == preRead[0] }
                    checksum = String(texts.reduce(0) { $0 + $1.utf8.count })
                    expected = String(preRead.reduce(0) { $0 + $1.utf8.count })
                case .snapshot:
                    elapsed = snapshots.withUnsafeMutableBufferPointer { buffer in
                        let start = DispatchTime.now().uptimeNanoseconds
                        for operation in 0 ..< iterations { buffer[operation % 64] = cache.snapshot(of: root) }
                        return DispatchTime.now().uptimeNanoseconds - start
                    }
                    valid = snapshots.allSatisfy { $0 == first }
                    checksum = String(snapshots.reduce(UInt64(0)) { $0 &+ Self.hash($1) })
                    expected = String(preconstructed.reduce(UInt64(0)) { $0 &+ Self.hash($1) })
                case .stringHash, .snapshotHash:
                    let start = DispatchTime.now().uptimeNanoseconds
                    for operation in 0 ..< iterations {
                        hashSum &+=
                            phase == .stringHash
                            ? Self.hash(preRead[operation % 64]) : Self.hash(preconstructed[operation % 64])
                    }
                    elapsed = DispatchTime.now().uptimeNanoseconds - start
                    var expectedSum: UInt64 = 0
                    for operation in 0 ..< iterations {
                        expectedSum &+=
                            phase == .stringHash
                            ? Self.hash(preRead[operation % 64]) : Self.hash(preconstructed[operation % 64])
                    }
                    valid = hashSum == expectedSum
                    checksum = String(hashSum)
                    expected = String(expectedSum)
                }
                XCTAssertTrue(valid)
                XCTAssertEqual(checksum, expected)
                samples.append(
                    StringCostTrial(
                        index: trial,
                        elapsedNanoseconds: elapsed,
                        nanosecondsPerOperation: Double(elapsed) / Double(iterations),
                        checksum: checksum,
                        expectedChecksum: expected,
                        resultsValidated: valid
                    )
                )
            }
            rows.append(
                StringCostRow(
                    content: content.rawValue,
                    strategy: strategy.rawValue,
                    phase: phase.rawValue,
                    iterations: iterations,
                    timingBoundary: phase.timingBoundary,
                    trials: samples,
                    resultsValidated: samples.allSatisfy(\.resultsValidated)
                )
            )
        }
        return rows
    }

    // Keep each public hash invocation observable rather than permitting an invariant loop to be hoisted.
    @inline(never) private static func hash(_ value: String) -> UInt64 { UInt64(truncatingIfNeeded: value.hashValue) }
    @inline(never) private static func hash(_ value: DependencySnapshot) -> UInt64 {
        UInt64(truncatingIfNeeded: value.hashValue)
    }
}

@MainActor
private final class StringMeasurementCounter { var measurements = 0 }

private enum StringCostPhase: String, CaseIterable {
    case dependencyRead = "dependency-read-64-slots"
    case snapshot = "snapshot-capture-64-slots"
    case stringHash = "string-hash-pre-read"
    case snapshotHash = "snapshot-hash-preconstructed"

    var timingBoundary: String {
        switch self {
        case .dependencyRead:
            "Selected dependency read including makeContiguousUTF8 only for contiguous-uikit-text, plus preallocated 64-slot String writes"
        case .snapshot:
            "SizeCache.snapshot capture of actual selected text/font key paths, including selected normalization, plus preallocated 64-slot snapshot writes"
        case .stringHash:
            "Public hashValue of 64 pre-read Strings, no getter/normalization in timing, plus UInt64 accumulation and non-inlined call"
        case .snapshotHash:
            "Public hashValue of 64 preconstructed snapshots, no capture in timing, plus UInt64 accumulation and non-inlined call"
        }
    }
}

private struct StringTrial: Encodable {
    let index: Int
    let orderIndex: Int
    let elapsedNanoseconds: UInt64
    let nanosecondsPerOperation: Double
    let checksum: Double
    let expectedChecksum: Double
    let resultsValidated: Bool
}

private struct StringDiagnostics: Encodable {
    let iterations: Int
    let hits: Int
    let misses: Int
    let measurementCount: Int
    let entryCount: Int
    let evictionObserved: Bool
    let returnHitValidated: Bool
    let distinctHeightsObserved: Bool
    let restoredResultValidated: Bool
    let resultsValidated: Bool
}

private struct StringBenchmarkRow: Encodable {
    let content: String
    let scenario: String
    let strategy: String
    let timingBoundary: String
    let iterations: Int
    let capacity: Int
    let trials: [StringTrial]
    let diagnostics: StringDiagnostics
    let resultsValidated: Bool
}

private struct StringCostTrial: Encodable {
    let index: Int
    let elapsedNanoseconds: UInt64
    let nanosecondsPerOperation: Double
    let checksum: String
    let expectedChecksum: String
    let resultsValidated: Bool
}

private struct StringCostRow: Encodable {
    let content: String
    let strategy: String
    let phase: String
    let iterations: Int
    let timingBoundary: String
    let trials: [StringCostTrial]
    let resultsValidated: Bool
}

private struct StringRepresentation: Encodable {
    let content: String
    let strategy: String
    let utf8Length: Int
    let isContiguousUTF8: Bool
    let rawUIKitIsContiguousUTF8: Bool
    let sourceIsContiguousUTF8: Bool
}

private struct StringBenchmarkReport: Encodable {
    let schemaVersion: Int
    let benchmarkEnabled: Bool
    let iterations: Int
    let trials: Int
    let capacity: Int
    let phaseIterations: Int
    let phaseTrials: Int
    let runtime: StringRuntime
    let rows: [StringBenchmarkRow]
    let costDiagnostics: [StringCostRow]
    let representations: [StringRepresentation]
    let phaseOrder = StringCostPhase.allCases.map(\.rawValue)
    let phaseInterpretation =
        "Fixed phase order; separate observations include buffer/call overhead and are not additive or suitable for exact subtraction. String hashing uses pre-read values; complete lookup includes all capture and normalization."
    let fixtureOwnership =
        "Fresh independent fixture per arm/trial; same native model and actual UITextView configuration; no timed counters; rotating four-arm order"
    let warmupIterationsPerView: Int
    let width = 180
    let fontPointSize = 17
}

private struct StringRuntime: Encodable {
    let deviceName: String
    let model: String
    let systemName: String
    let systemVersion: String
    let isSimulator: Bool

    @MainActor init() {
        deviceName = UIDevice.current.name
        model = UIDevice.current.model
        systemName = UIDevice.current.systemName
        systemVersion = UIDevice.current.systemVersion
        #if targetEnvironment(simulator)
        isSimulator = true
        #else
        isSimulator = false
        #endif
    }
}
#endif
