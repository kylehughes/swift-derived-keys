#if canImport(UIKit)
import DerivedKeys
import DerivedKeysUI
import DerivedKeysUIExample
import Dispatch
import UIKit
import XCTest

final class UIKitSizingBenchmarkTests: XCTestCase {
    @MainActor
    func testSizingBenchmarks() throws {
        let options = try BenchmarkOptions()
        var rows: [BenchmarkRow] = []
        for workload in Workload.allCases {
            var scenarios: [Scenario] = [
                workload == .documentParent ? .warmParent : .warmOneView,
                .equivalentPoolViews, .widthChanges, .contentFontChanges, .mixedBounded,
            ]
            if workload == .documentParent { scenarios.insert(.parentOnlySpacingMiss, at: 2) }
            for scenario in scenarios {
                let requests = scenario.requests(count: options.iterations, initialVariant: workload.initialVariant)
                let diagnostic = Fixture(workload: workload, scenario: scenario, counted: true)
                let diagnostics = diagnostic.diagnose(requests, observeMembership: options.enabled)
                var trials: [Trial] = []
                for index in 0 ..< options.trials {
                    let direct = Fixture(workload: workload, scenario: scenario)
                    let cached = Fixture(workload: workload, scenario: scenario)
                    direct.prepare()
                    cached.prepare()
                    var directResults = Array(repeating: CGSize.zero, count: requests.count)
                    var cachedResults = Array(repeating: CGSize.zero, count: requests.count)
                    let directElapsed: UInt64
                    let cachedElapsed: UInt64
                    if index.isMultiple(of: 2) {
                        directElapsed = direct.run(requests, cached: false, results: &directResults)
                        cachedElapsed = cached.run(requests, cached: true, results: &cachedResults)
                    } else {
                        cachedElapsed = cached.run(requests, cached: true, results: &cachedResults)
                        directElapsed = direct.run(requests, cached: false, results: &directResults)
                    }
                    XCTAssertEqual(directResults, cachedResults, "\(workload.rawValue)/\(scenario.rawValue)")
                    XCTAssertTrue(directResults.allSatisfy { $0.width.isFinite && $0.height.isFinite && $0.height > 0 })
                    cached.assertBounds()
                    trials.append(
                        Trial(
                            index: index,
                            directNanoseconds: directElapsed,
                            cachedNanoseconds: cachedElapsed,
                            directNanosecondsPerOperation: Double(directElapsed) / Double(requests.count),
                            cachedNanosecondsPerOperation: Double(cachedElapsed) / Double(requests.count),
                            directFirst: index.isMultiple(of: 2),
                            resultsValidated: directResults == cachedResults,
                            checksum: cachedResults.reduce(0) { $0 + Double($1.width + $1.height) },
                            expectedChecksum: directResults.reduce(0) { $0 + Double($1.width + $1.height) }
                        )
                    )
                }
                rows.append(
                    BenchmarkRow(
                        workload: workload.rawValue,
                        scenario: scenario.rawValue,
                        timingBoundary: scenario.timingBoundary,
                        iterations: options.iterations,
                        capacity: Fixture.capacity,
                        trials: trials,
                        diagnostics: diagnostics,
                        resultsValidated: trials.allSatisfy(\.resultsValidated)
                    )
                )
            }
        }
        let report = BenchmarkReport(
            schemaVersion: 1,
            benchmarkEnabled: options.enabled,
            iterations: options.iterations,
            trials: options.trials,
            capacity: Fixture.capacity,
            warmupIterationsPerView: Fixture.warmupIterations,
            runtime: Runtime(),
            rows: rows,
            costDiagnostics: [Workload.labelSingle, .labelMultiline, .labelAttributed, .textView]
                .flatMap {
                    Fixture(workload: $0, scenario: .warmOneView)
                        .costDiagnostics(
                            iterations: options.enabled ? 512 : 8,
                            trialCount: options.enabled ? 5 : 1
                        )
                }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let attachment = XCTAttachment(data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
        attachment.name = "DerivedKeysUIKitBenchmarks.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct BenchmarkOptions {
    let enabled: Bool
    let iterations: Int
    let trials: Int

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
        guard let number = Int(value), range.contains(number) else { throw ConfigurationError.invalidInteger }
        return number
    }

    private enum ConfigurationError: Error {
        case invalidInteger
        case releaseRequired
    }
}

private enum Workload: String, CaseIterable {
    case labelSingle = "UILabel-single-line"
    case labelMultiline = "UILabel-multiline"
    case labelAttributed = "UILabel-attributed"
    case textView = "UITextView"
    case documentText = "DocumentContentView-text"
    case documentButton = "DocumentContentView-button"
    case documentParent = "DocumentContentView-parent"

    var initialVariant: Int {
        switch self {
        case .labelSingle: 0
        case .labelMultiline: 1
        case .labelAttributed: 3
        case .textView: 2
        case .documentText, .documentButton, .documentParent: 1
        }
    }

    var isDocument: Bool {
        switch self {
        case .documentText, .documentButton, .documentParent: true
        default: false
        }
    }
}

private enum Scenario: String {
    case warmOneView = "warm-one-view"
    case equivalentPoolViews = "equivalent-pool-views"
    case warmParent = "warm-parent"
    case parentOnlySpacingMiss = "parent-only-spacing-miss"
    case widthChanges = "width-changes"
    case contentFontChanges = "content-font-changes"
    case mixedBounded = "mixed-bounded"

    var changesConfiguration: Bool {
        switch self {
        case .warmOneView, .equivalentPoolViews, .warmParent: false
        default: true
        }
    }

    var timingBoundary: String {
        if changesConfiguration {
            return
                "configure-plus-measure; identical eager assignments of prebuilt text, fonts, immutable attributed strings and document trait updates in both arms"
        }
        if self == .equivalentPoolViews {
            return
                "preconfigured-measurement-only; eight initially unfitted views; separate equivalent seed warms UIKit and shared cache; direct document controls retained before timing"
        }
        return
            "preconfigured-measurement-only; all request views UIKit-warmed; direct document controls retained before timing"
    }

    var poolCount: Int { self == .equivalentPoolViews ? 9 : 1 }

    func requests(count: Int, initialVariant: Int) -> [Request] {
        (0 ..< count)
            .map { index in
                var request = Request(
                    view: self == .equivalentPoolViews ? index % 8 + 1 : 0,
                    variant: initialVariant
                )
                switch self {
                case .parentOnlySpacingMiss:
                    request.spacing = CGFloat(index + 9)
                case .widthChanges:
                    request.width = index.isMultiple(of: 2) ? 180 : 320
                case .contentFontChanges:
                    request.variant = index % 4
                    request.font = index % 3
                case .mixedBounded:
                    // Adjacent repeated keys provide hits; the remainder exceeds the fixed capacity.
                    let position = index % 48
                    request.variant = position < 16 ? position / 2 : position - 8
                    request.font = request.variant % 3
                    request.width = request.variant.isMultiple(of: 2) ? 180 : 320
                default: break
                }
                return request
            }
    }
}

private struct Request {
    var view: Int
    var variant = 0
    var font = 0
    var width: CGFloat = 180
    var height: CGFloat = .greatestFiniteMagnitude
    var spacing: CGFloat = 8

    var proposal: CGSize { CGSize(width: width, height: height) }
}

@MainActor
private enum PreparedInputs {
    static let fonts = [17, 24, 32].map { UIFont.systemFont(ofSize: CGFloat($0)) }
    static let categories: [UIContentSizeCategory] = [
        .large, .accessibilityMedium, .accessibilityExtraExtraExtraLarge,
    ]
    static let texts: [String] = {
        let texts = [
            "Short title.",
            String(repeating: "A document has paragraphs that wrap at the available width. ", count: 4),
            String(repeating: "Long text includes punctuation, dates, and several measured lines. ", count: 24),
            "Attributed typography mixes emphasis and spacing. "
                + String(repeating: "A second sentence wraps across lines. ", count: 8),
        ]
        return (0 ..< 40).map { texts[$0 % texts.count] + " Variant \($0)." }
    }()
    static let attributed: [[NSAttributedString]] = texts.map { content in
        fonts.map { font in
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            let text = NSMutableAttributedString(
                string: content,
                attributes: [.font: font, .paragraphStyle: paragraph.copy() as! NSParagraphStyle, .kern: 0.3]
            )
            text.addAttribute(
                .font,
                value: UIFont.boldSystemFont(ofSize: font.pointSize),
                range: NSRange(location: 0, length: min(12, text.length))
            )
            return text.copy() as! NSAttributedString
        }
    }
}

@MainActor
private final class Leaf {
    let control: UIView
    let label: UILabel?
    let textView: UITextView?
    let workload: Workload

    init(workload: Workload) {
        self.workload = workload
        if workload == .textView {
            let text = UITextView()
            text.isScrollEnabled = false
            text.isEditable = false
            text.isSelectable = false
            text.textContainerInset = .zero
            text.textContainer.lineFragmentPadding = 0
            control = text
            textView = text
            label = nil
        } else {
            let label = UILabel()
            label.numberOfLines = workload == .labelSingle ? 1 : 0
            label.lineBreakMode = .byWordWrapping
            control = label
            self.label = label
            textView = nil
        }
        control.semanticContentAttribute = .forceLeftToRight
    }

    func configure(_ request: Request) {
        let font = PreparedInputs.fonts[request.font]
        if let textView {
            textView.font = font
            textView.text = PreparedInputs.texts[request.variant]
        } else if let label {
            label.font = font
            if workload == .labelAttributed {
                label.attributedText = PreparedInputs.attributed[request.variant][request.font]
            } else {
                label.text = PreparedInputs.texts[request.variant]
            }
        }
    }
}

@MainActor
private final class Fixture {
    static let capacity = 16
    static let warmupIterations = 4

    let workload: Workload
    let scenario: Scenario
    private let counted: Bool
    private var leafMeasurements = 0
    private var labelCache: SizeCache<UILabel>?
    private var textViewCache: SizeCache<UITextView>?
    private var documents: [DocumentContentView] = []
    private var leaves: [Leaf] = []
    private var hosts: [UIViewController] = []
    private var containers: [UIViewController] = []
    private var retainedText: [UITextView] = []
    private var retainedButtons: [UIButton] = []
    private var bundle = DocumentSizeCaches(capacity: capacity)

    init(workload: Workload, scenario: Scenario, counted: Bool = false) {
        self.workload = workload
        self.scenario = scenario
        self.counted = counted
        if workload.isDocument {
            for _ in 0 ..< scenario.poolCount {
                let document = DocumentContentView(caches: bundle)
                let host = UIViewController()
                let container = UIViewController()
                container.addChild(host)
                container.view.addSubview(host.view)
                host.didMove(toParent: container)
                host.view.addSubview(document)
                documents.append(document)
                hosts.append(host)
                containers.append(container)
            }
        } else {
            leaves = (0 ..< scenario.poolCount).map { _ in Leaf(workload: workload) }
        }
        resetStorage()
    }

    func prepare() {
        resetStorage()
        for index in 0 ..< scenario.poolCount {
            let request = Request(view: index, variant: workload.initialVariant)
            configure(request, initial: true)
        }
        retainedText = documents.map(\.textView)
        retainedButtons = documents.map(\.button)
        // The pool scenario fits only a separate seed, leaving all eight request controls initially unfitted.
        _ = cached(Request(view: 0, variant: workload.initialVariant))
        // Configuration is eager in both arms; retain the existing controls before warming UIKit.
        for index in 0 ..< scenario.poolCount where scenario != .equivalentPoolViews || index == 0 {
            let request = Request(view: index, variant: workload.initialVariant)
            for _ in 0 ..< Self.warmupIterations { _ = direct(request) }
        }
        leafMeasurements = 0
    }

    @inline(never)
    func run(_ requests: [Request], cached useCache: Bool, results: inout [CGSize]) -> UInt64 {
        // Resolve uniqueness and acquire writable storage before starting the clock.
        results.withUnsafeMutableBufferPointer { buffer in
            let start = DispatchTime.now().uptimeNanoseconds
            for index in requests.indices {
                let request = requests[index]
                if scenario.changesConfiguration { configure(request) }
                buffer[index] = useCache ? cached(request) : direct(request)
            }
            return DispatchTime.now().uptimeNanoseconds - start
        }
    }

    func assertBounds() {
        let entries = entries()
        XCTAssertTrue([entries.parent, entries.text, entries.button, entries.leaf].allSatisfy { $0 <= Self.capacity })
    }

    func diagnose(_ requests: [Request], observeMembership: Bool) -> Diagnostics {
        var hits = Counts()
        var misses = Counts()
        if workload.isDocument && observeMembership {
            // Public removal and count APIs reveal membership without a parallel cache implementation.
            // Reconstruct each prefix because probing removes the inspected entry.
            for index in requests.indices {
                prepare()
                for earlier in requests[..<index] {
                    if scenario.changesConfiguration { configure(earlier) }
                    _ = cached(earlier)
                }
                let request = requests[index]
                if scenario.changesConfiguration { configure(request) }
                let view = documents[request.view]
                if workload == .documentParent {
                    let parentHit = contains(cache: bundle.contentSizes, root: view, proposal: request.proposal)
                    if parentHit {
                        hits.parent += 1
                    } else {
                        misses.parent += 1
                        let inner = innerProposal(request, view: view)
                        record(
                            contains(cache: bundle.textSizes, root: view.textView, proposal: inner),
                            hits: &hits.text,
                            misses: &misses.text
                        )
                        record(
                            contains(cache: bundle.buttonSizes, root: view.button, proposal: inner),
                            hits: &hits.button,
                            misses: &misses.button
                        )
                    }
                } else if workload == .documentText {
                    record(
                        contains(cache: bundle.textSizes, root: view.textView, proposal: request.proposal),
                        hits: &hits.text,
                        misses: &misses.text
                    )
                } else {
                    record(
                        contains(cache: bundle.buttonSizes, root: view.button, proposal: request.proposal),
                        hits: &hits.button,
                        misses: &misses.button
                    )
                }
            }
        }
        prepare()
        var validated = true
        var evictionObserved = false
        for request in requests {
            if scenario.changesConfiguration { configure(request) }
            if workload.isDocument {
                XCTAssertEqual(
                    documents[request.view].traitCollection.preferredContentSizeCategory,
                    PreparedInputs.categories[request.font],
                    "The actual document dependency must see the requested Dynamic Type category."
                )
            }
            let before = leafMeasurements
            let actual = cached(request)
            let expected = direct(request)
            XCTAssertEqual(actual, expected)
            validated = validated && actual == expected
            if !workload.isDocument {
                record(leafMeasurements == before, hits: &hits.leaf, misses: &misses.leaf)
            }
            assertBounds()
        }
        let finalEntries = entries()
        // More observed misses than retained entries shows that some inserted result was evicted.
        evictionObserved =
            misses.parent > finalEntries.parent && finalEntries.parent == Self.capacity
            || misses.text > finalEntries.text && finalEntries.text == Self.capacity
            || misses.button > finalEntries.button && finalEntries.button == Self.capacity
            || misses.leaf > finalEntries.leaf && finalEntries.leaf == Self.capacity
        if observeMembership && scenario == .mixedBounded && requests.count >= 48 {
            XCTAssertGreaterThan(hits.total, 0)
            XCTAssertGreaterThan(misses.total, 0)
            if workload != .documentButton { XCTAssertTrue(evictionObserved) }
        }
        return Diagnostics(
            ownership: workload.isDocument
                ? (observeMembership
                    ? "Actual DocumentSizeCaches; destructive membership probes on independently replayed exact prefixes; misses imply measurements"
                    : "Smoke validation of actual DocumentSizeCaches; membership prefix probes reserved for opt-in benchmark")
                : "Actual UIKit text/font/attributedText key paths; closure counter in untimed diagnostic replay only",
            observedMembershipHits: hits,
            observedMembershipMisses: misses,
            measurementCountsInferredFromMisses: workload.isDocument,
            entryCounts: finalEntries,
            evictionObserved: evictionObserved,
            resultsValidated: validated
        )
    }

    func costDiagnostics(iterations: Int, trialCount: Int) -> [CostRow] {
        prepare()
        let leaf = leaves[0]
        if let label = leaf.label {
            return measureCostPhases(
                cache: labelCache!,
                root: label,
                iterations: iterations,
                trialCount: trialCount
            )
        }
        return measureCostPhases(
            cache: textViewCache!,
            root: leaf.textView!,
            iterations: iterations,
            trialCount: trialCount,
            textGetter: { leaf.textView!.text ?? "" }
        )
    }

    private func measureCostPhases<Control: UIView>(
        cache: SizeCache<Control>,
        root: Control,
        iterations: Int,
        trialCount: Int,
        textGetter: (@MainActor () -> String)? = nil
    ) -> [CostRow] {
        let proposal = Request(view: 0).proposal
        let first = cache.snapshot(of: root)
        let expectedSize = root.sizeThatFits(proposal)
        let expectedText = textGetter?()
        let preconstructed = Array(repeating: first, count: 64)
        var phases = [CostPhase.direct, .snapshot, .hash, .lookup]
        if textGetter != nil { phases.append(.textGetter) }
        var rows: [CostRow] = []
        for phase in phases {
            var trials: [CostTrial] = []
            for index in 0 ..< trialCount {
                // Reuse stable inputs and the same warmed view and cache; allocate buffers and resolve uniqueness before timing.
                var sizes = Array(repeating: CGSize.zero, count: iterations)
                var snapshots = preconstructed
                var texts = Array(repeating: expectedText ?? "", count: 64)
                var hashSum: UInt64 = 0
                let elapsed: UInt64
                let checksum: String
                let expectedChecksum: String
                let validated: Bool
                switch phase {
                case .direct, .lookup:
                    elapsed = sizes.withUnsafeMutableBufferPointer { buffer in
                        let start = DispatchTime.now().uptimeNanoseconds
                        for operation in 0 ..< iterations {
                            buffer[operation] =
                                phase == .direct
                                ? root.sizeThatFits(proposal) : cache.size(of: root, toFit: proposal)
                        }
                        return DispatchTime.now().uptimeNanoseconds - start
                    }
                    validated = sizes.allSatisfy { $0 == expectedSize }
                    checksum = String(sizes.reduce(0.0) { $0 + Double($1.width + $1.height) })
                    expectedChecksum = String(
                        Array(repeating: expectedSize, count: iterations)
                            .reduce(0.0) { $0 + Double($1.width + $1.height) }
                    )
                case .snapshot:
                    elapsed = snapshots.withUnsafeMutableBufferPointer { buffer in
                        let start = DispatchTime.now().uptimeNanoseconds
                        for operation in 0 ..< iterations {
                            buffer[operation % 64] = cache.snapshot(of: root)
                        }
                        return DispatchTime.now().uptimeNanoseconds - start
                    }
                    validated = snapshots.allSatisfy { $0 == first }
                    checksum = String(Self.hashSum(snapshots))
                    expectedChecksum = String(Self.hashSum(preconstructed))
                case .hash:
                    let start = DispatchTime.now().uptimeNanoseconds
                    for operation in 0 ..< iterations {
                        hashSum &+= UInt64(truncatingIfNeeded: preconstructed[operation % 64].hashValue)
                    }
                    elapsed = DispatchTime.now().uptimeNanoseconds - start
                    var expected: UInt64 = 0
                    for operation in 0 ..< iterations {
                        expected &+= UInt64(truncatingIfNeeded: preconstructed[operation % 64].hashValue)
                    }
                    checksum = String(hashSum)
                    expectedChecksum = String(expected)
                    validated = hashSum == expected
                case .textGetter:
                    elapsed = texts.withUnsafeMutableBufferPointer { buffer in
                        let start = DispatchTime.now().uptimeNanoseconds
                        for operation in 0 ..< iterations {
                            buffer[operation % 64] = textGetter!()
                        }
                        return DispatchTime.now().uptimeNanoseconds - start
                    }
                    validated = texts.allSatisfy { $0 == expectedText }
                    checksum = String(texts.reduce(0) { $0 + $1.utf8.count })
                    expectedChecksum = String(64 * (expectedText?.utf8.count ?? 0))
                }
                XCTAssertTrue(validated, "\(workload.rawValue)/\(phase.rawValue)")
                XCTAssertEqual(checksum, expectedChecksum)
                XCTAssertEqual(cache.count, 1)
                trials.append(
                    CostTrial(
                        index: index,
                        elapsedNanoseconds: elapsed,
                        nanosecondsPerOperation: Double(elapsed) / Double(iterations),
                        checksum: checksum,
                        expectedChecksum: expectedChecksum,
                        resultsValidated: validated
                    )
                )
            }
            rows.append(
                CostRow(
                    workload: workload.rawValue,
                    phase: phase.rawValue,
                    iterations: iterations,
                    trials: trials,
                    timingBoundary: phase.timingBoundary,
                    resultsValidated: trials.allSatisfy(\.resultsValidated)
                )
            )
        }
        return rows
    }

    private static func hashSum(_ snapshots: [DependencySnapshot]) -> UInt64 {
        snapshots.reduce(0) { $0 &+ UInt64(truncatingIfNeeded: $1.hashValue) }
    }

    private func resetStorage() {
        bundle = DocumentSizeCaches(capacity: Self.capacity)
        if workload == .textView {
            if counted {
                textViewCache = SizeCache(dependingOn: \.text, \.font, capacity: Self.capacity) {
                    [unowned self] view, proposal in
                    self.leafMeasurements += 1
                    return view.sizeThatFits(proposal)
                }
            } else {
                textViewCache = SizeCache(dependingOn: \.text, \.font, capacity: Self.capacity)
            }
        } else if !workload.isDocument {
            if counted {
                let measure: @MainActor (UILabel, CGSize) -> CGSize = { [unowned self] view, proposal in
                    self.leafMeasurements += 1
                    return view.sizeThatFits(proposal)
                }
                if workload == .labelAttributed {
                    labelCache = SizeCache(
                        dependingOn: \.attributedText,
                        \.font,
                        \.numberOfLines,
                        \.lineBreakMode,
                        capacity: Self.capacity,
                        measure: measure
                    )
                } else {
                    labelCache = SizeCache(
                        dependingOn: \.text,
                        \.font,
                        \.numberOfLines,
                        \.lineBreakMode,
                        capacity: Self.capacity,
                        measure: measure
                    )
                }
            } else if workload == .labelAttributed {
                labelCache = SizeCache(
                    dependingOn: \.attributedText,
                    \.font,
                    \.numberOfLines,
                    \.lineBreakMode,
                    capacity: Self.capacity
                )
            } else {
                labelCache = SizeCache(
                    dependingOn: \.text,
                    \.font,
                    \.numberOfLines,
                    \.lineBreakMode,
                    capacity: Self.capacity
                )
            }
        }
    }

    private func configure(_ request: Request, initial: Bool = false) {
        let changesContentAndFont = initial || scenario == .contentFontChanges || scenario == .mixedBounded
        guard workload.isDocument else {
            if changesContentAndFont { leaves[request.view].configure(request) }
            return
        }
        let view = documents[request.view]
        if initial { view.isExpanded = true }
        if initial || scenario == .parentOnlySpacingMiss { view.spacing = request.spacing }
        if changesContentAndFont {
            view.content = PreparedInputs.texts[request.variant]
            if #available(iOS 17, *) {
                hosts[request.view].traitOverrides.preferredContentSizeCategory =
                    PreparedInputs.categories[request.font]
                hosts[request.view].updateTraitsIfNeeded()
                view.updateTraitsIfNeeded()
            } else {
                containers[request.view]
                    .setOverrideTraitCollection(
                        UITraitCollection(preferredContentSizeCategory: PreparedInputs.categories[request.font]),
                        forChild: hosts[request.view]
                    )
            }
        }
    }

    private func cached(_ request: Request) -> CGSize {
        if !workload.isDocument {
            let leaf = leaves[request.view]
            if let label = leaf.label { return labelCache!.size(of: label, toFit: request.proposal) }
            return textViewCache!.size(of: leaf.textView!, toFit: request.proposal)
        }
        let view = documents[request.view]
        switch workload {
        case .documentText: return bundle.textSizes.size(of: view.textView, toFit: request.proposal)
        case .documentButton: return bundle.buttonSizes.size(of: view.button, toFit: request.proposal)
        default: return bundle.contentSizes.size(of: view, toFit: request.proposal)
        }
    }

    private func direct(_ request: Request) -> CGSize {
        guard workload.isDocument else { return leaves[request.view].control.sizeThatFits(request.proposal) }
        let view = documents[request.view]
        let preconfigured = !scenario.changesConfiguration && !retainedText.isEmpty
        switch workload {
        case .documentText:
            return (preconfigured ? retainedText[request.view] : view.textView).sizeThatFits(request.proposal)
        case .documentButton:
            return (preconfigured ? retainedButtons[request.view] : view.button).sizeThatFits(request.proposal)
        default:
            let inner = innerProposal(request, view: view)
            let text = (preconfigured ? retainedText[request.view] : view.textView).sizeThatFits(inner)
            let button =
                view.showsButton
                ? (preconfigured ? retainedButtons[request.view] : view.button).sizeThatFits(inner).height : 0
            let gap = view.showsButton ? view.spacing : 0
            return CGSize(width: request.width, height: 2 * view.padding + text.height + gap + button)
        }
    }

    private func innerProposal(_ request: Request, view: DocumentContentView) -> CGSize {
        CGSize(width: max(0, request.width - 2 * view.padding), height: .greatestFiniteMagnitude)
    }

    private func contains<Root>(cache: SizeCache<Root>, root: Root, proposal: CGSize) -> Bool {
        let before = cache.count
        cache.removeSize(of: root, toFit: proposal)
        return cache.count < before
    }

    private func entries() -> Counts {
        Counts(
            parent: bundle.contentSizes.count,
            text: bundle.textSizes.count,
            button: bundle.buttonSizes.count,
            leaf: labelCache?.count ?? textViewCache?.count ?? 0
        )
    }

    private func record(_ hit: Bool, hits: inout Int, misses: inout Int) {
        if hit { hits += 1 } else { misses += 1 }
    }
}

private struct Counts: Encodable {
    var parent = 0
    var text = 0
    var button = 0
    var leaf = 0
    var total: Int { parent + text + button + leaf }
}

private struct Diagnostics: Encodable {
    let ownership: String
    let observedMembershipHits: Counts
    let observedMembershipMisses: Counts
    let measurementCountsInferredFromMisses: Bool
    let entryCounts: Counts
    let evictionObserved: Bool
    let resultsValidated: Bool
}

private struct Trial: Encodable {
    let index: Int
    let directNanoseconds: UInt64
    let cachedNanoseconds: UInt64
    let directNanosecondsPerOperation: Double
    let cachedNanosecondsPerOperation: Double
    let directFirst: Bool
    let resultsValidated: Bool
    let checksum: Double
    let expectedChecksum: Double
}

private struct BenchmarkRow: Encodable {
    let workload: String
    let scenario: String
    let timingBoundary: String
    let iterations: Int
    let capacity: Int
    let trials: [Trial]
    let diagnostics: Diagnostics
    let resultsValidated: Bool
}

private struct BenchmarkReport: Encodable {
    let schemaVersion: Int
    let benchmarkEnabled: Bool
    let iterations: Int
    let trials: Int
    let capacity: Int
    let warmupIterationsPerView: Int
    let runtime: Runtime
    let rows: [BenchmarkRow]
    let costDiagnostics: [CostRow]
    let costDiagnosticsInterpretation =
        "Separate stable-input phases include their observation overhead; subtracting phases does not isolate LRU bookkeeping"
    let standaloneFontPointSizes = [17, 24, 32]
    let documentFontCategories = ["large", "accessibilityMedium", "accessibilityExtraExtraExtraLarge"]
    let widths = [180, 320]
    let fixtureOwnership = "Fresh independent direct and cached fixtures per trial; fixed 16-entry cache per recipe"
    let contentInputs =
        "Short title, multiline paragraph, long text, attributed typography; mixed trace appends semantic variant"
    let attributedConfiguration =
        "Prebuilt immutable attributed snapshot; font plus bold first 12 UTF-16 units, 3-point line spacing, 0.3 kern"
}

private enum CostPhase: String {
    case direct = "direct-warm-fit"
    case snapshot = "snapshot-capture-64-slots"
    case hash = "hash-preconstructed-snapshot"
    case lookup = "warm-size-lookup"
    case textGetter = "text-getter-64-slots"

    var timingBoundary: String {
        switch self {
        case .direct: "Warmed UIKit sizeThatFits plus preallocated size-buffer writes"
        case .snapshot: "Actual configured key-path capture plus 64-slot snapshot-buffer writes; hashing after timing"
        case .hash: "Public hashValue of 64 preconstructed equivalent snapshots plus UInt64 accumulation"
        case .lookup: "Full warmed SizeCache.size lookup plus preallocated size-buffer writes"
        case .textGetter:
            "UITextView.text getter plus 64-slot String-buffer writes; validation and UTF-8 counts after timing"
        }
    }
}

private struct CostRow: Encodable {
    let workload: String
    let phase: String
    let iterations: Int
    let trials: [CostTrial]
    let timingBoundary: String
    let resultsValidated: Bool
}

private struct CostTrial: Encodable {
    let index: Int
    let elapsedNanoseconds: UInt64
    let nanosecondsPerOperation: Double
    let checksum: String
    let expectedChecksum: String
    let resultsValidated: Bool
}

private struct Runtime: Encodable {
    let deviceName: String
    let model: String
    let systemName: String
    let systemVersion: String
    let isSimulator: Bool

    @MainActor
    init() {
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
