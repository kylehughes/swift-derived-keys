import DerivedKeys
import Testing

struct DependencySnapshotTests {
    private final class ValueOperations {
        var equalityCalls = 0
        var hashCalls = 0
    }

    private struct TrackedValue: Hashable {
        let value: Int
        let operations: ValueOperations

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.operations.equalityCalls += 1
            return lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            operations.hashCalls += 1
            hasher.combine(value)
        }
    }

    private struct Collision: Hashable {
        let value: Int

        func hash(into hasher: inout Hasher) {
            hasher.combine(0)
        }
    }

    private enum ExportFormat: CaseIterable, Hashable {
        case plainText
        case markdown
    }

    private struct ExportOptions: Hashable {
        let format: ExportFormat
        let includesHeading: Bool
    }

    private struct Document {
        var paragraphs: [String]
        var selectedParagraph: Int?
        var scrollOffset: Double
    }

    @Test func completeValuesAndConcreteTypesDetermineEquality() {
        let integer = DependencySnapshot(value: Int(1))
        #expect(integer == DependencySnapshot(value: Int(1)))
        #expect(integer != DependencySnapshot(value: Int(2)))
        #expect(integer != DependencySnapshot(value: Int8(1)))
        #expect(integer != DependencySnapshot(value: Optional(1)))
        #expect(AnyHashable(Int(1)) == AnyHashable(Double(1)))
        #expect(integer != DependencySnapshot(value: Double(1)))
        #expect(integer != DependencySnapshot(value: AnyHashable(Int(1))))
        #expect(
            DependencySnapshot(value: AnyHashable(Int(1)))
                == DependencySnapshot(value: AnyHashable(Double(1)))
        )
    }

    @Test func hashCollisionsDoNotMergeValues() throws {
        let first = DependencySnapshot(value: Collision(value: 1))
        let second = DependencySnapshot(value: Collision(value: 2))
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
        #expect(try DependencySnapshot(children: [first]) != DependencySnapshot(children: [second]))
    }

    @Test func equalValuesOfDifferentConcreteTypesAreUnequal() throws {
        #expect(DependencySnapshot(value: 1 as Int) != DependencySnapshot(value: 1 as Int8))
        #expect(DependencySnapshot(value: [1] as [Int]) != DependencySnapshot(value: [1] as [Int8]))
        #expect(
            DependencySnapshot(value: "abc") != DependencySnapshot(value: Substring("abc"))
        )
        #expect(
            DependencySnapshot(value: [1] as [Int]) != DependencySnapshot(value: [1] as Set<Int>)
        )
        #expect(
            try DependencySnapshot(children: [DependencySnapshot(value: 1 as Int)])
                != DependencySnapshot(children: [DependencySnapshot(value: 1 as Int8)])
        )
        #expect(
            KeySource<Void>("a", value: 1 as Int).snapshot(for: ())
                != KeySource<Void>("a", value: 1 as Int8).snapshot(for: ())
        )
    }

    @Test func collidingLeafHashesStayDistinct() {
        let snapshots = (0 ..< 32).map { DependencySnapshot(value: Collision(value: $0)) }
        #expect(Set(snapshots).count == snapshots.count)
        #expect(DependencySnapshot(value: Collision(value: 7)) == snapshots[7])
        #expect(DependencySnapshot(value: Collision(value: 7)).hashValue == snapshots[7].hashValue)
        #expect(snapshots[0] != snapshots[1])
    }

    @Test func snapshotsAndCopiesCompareEqualWithoutInspectingValues() {
        let operations = ValueOperations()
        let snapshot = DependencySnapshot(value: TrackedValue(value: 1, operations: operations))
        let copy = snapshot
        #expect(snapshot == snapshot)
        #expect(snapshot == copy)
        #expect(operations.equalityCalls == 0)
        let separate = DependencySnapshot(value: TrackedValue(value: 1, operations: operations))
        #expect(snapshot == separate)
        #expect(operations.equalityCalls > 0)
    }

    @Test func directSnapshotsEqualSourceProducedSnapshots() throws {
        #expect(DependencySnapshot(value: "text") == KeySource<Void>("", value: "text").snapshot(for: ()))
        #expect(
            DependencySnapshot(value: 3) == KeySource<Int>("", provider: { $0 }).snapshot(for: 3)
        )
        let direct = try DependencySnapshot(children: [
            DependencySnapshot(value: 1), DependencySnapshot(value: "two"),
        ])
        let source = try KeySource<Void>(
            "",
            children: [KeySource("", value: 1), KeySource("", value: "two")]
        )
        #expect(direct == source.snapshot(for: ()))
        #expect(direct.hashValue == source.snapshot(for: ()).hashValue)
        #expect(try direct != KeySource<Void>("label", children: []).snapshot(for: ()))
    }

    @Test func arraySnapshotsRetainConcreteEqualityAndHashing() {
        let operations = ValueOperations()
        let values = [1, 2, 3].map { TrackedValue(value: $0, operations: operations) }
        let snapshot = DependencySnapshot(value: values)
        let equivalentSnapshots = [
            DependencySnapshot(value: values),
            KeySource<Void>("", value: values).snapshot(for: ()),
            KeySource<[TrackedValue]>("", provider: { $0 }).snapshot(for: values),
            KeySource<Void>("", provider: { values }).snapshot(for: ()),
        ]

        for equivalent in equivalentSnapshots {
            #expect(snapshot == equivalent)
        }
        // Array equality recognizes shared storage without comparing elements.
        // Erasing each array element loses this concrete collection behavior.
        #expect(operations.equalityCalls == 0)

        let separateValues = values.map { TrackedValue(value: $0.value, operations: operations) }
        let separateSnapshot = DependencySnapshot(value: separateValues)
        #expect(snapshot == separateSnapshot)
        #expect(operations.equalityCalls > 0)
        #expect(snapshot.hashValue == separateSnapshot.hashValue)
        #expect(operations.hashCalls > 0)
    }

    @Test func arraySnapshotsPreserveValuesOrderMultiplicityAndElementTypes() {
        let arrays = [[Int](), [1], [2], [1, 2], [2, 1], [1, 1], [1, 2, 2]]
        let snapshots = arrays.map { DependencySnapshot(value: $0) }
        #expect(Set(snapshots).count == arrays.count)
        #expect(DependencySnapshot(value: [Int(1)]) != DependencySnapshot(value: [Int8(1)]))
        #expect(DependencySnapshot(value: [Int(1)]) != DependencySnapshot(value: [Double(1)]))
    }

    @Test func compositionsPreserveOrderMultiplicityNestingAndEmptyBoundaries() throws {
        let first = DependencySnapshot(value: 1)
        let second = DependencySnapshot(value: 2)
        let empty = try DependencySnapshot(children: [])
        let ordered = try DependencySnapshot(children: [first, second])
        let reversed = try DependencySnapshot(children: [second, first])
        let repeated = try DependencySnapshot(children: [first, second, second])
        let nested = try DependencySnapshot(children: [DependencySnapshot(children: [first]), second])
        let withEmpty = try DependencySnapshot(children: [first, second, empty])
        #expect(Set([ordered, reversed, repeated, nested, withEmpty, empty]).count == 6)
        #expect(empty == (try DependencySnapshot(children: [])))
        #expect(empty != DependencySnapshot(value: [Int]()))
        #expect(ordered == (try DependencySnapshot(children: [first, second])))
    }

    @Test func maximumDepthIsAcceptedAndNextLevelIsRejected() throws {
        #expect(DependencySnapshot.maximumDepth == 64)
        #expect(KeySource<Void>.maximumDepth == DependencySnapshot.maximumDepth)
        for initial in [DependencySnapshot(value: 1), try DependencySnapshot(children: [])] {
            var snapshot = initial
            for _ in 1 ..< DependencySnapshot.maximumDepth {
                snapshot = try DependencySnapshot(children: [snapshot])
            }
            #expect(snapshot == snapshot)
            #expect(Set([snapshot]).contains(snapshot))
            #expect(throws: DependencySnapshot.ConstructionError.maximumDepthExceeded) {
                try DependencySnapshot(children: [snapshot])
            }
        }
    }

    @Test func directSnapshotsMatchEquivalentEmptyLabelSources() throws {
        let first = DependencySnapshot(value: "content")
        let second = DependencySnapshot(value: 3)
        let source = try KeySource<Void>(
            "",
            children: [KeySource("", value: "content"), KeySource("", value: 3)]
        )
        #expect(first == KeySource<Void>("", value: "content").snapshot(for: ()))
        #expect(try DependencySnapshot(children: [first, second]) == source.snapshot(for: ()))
        #expect(
            try DependencySnapshot(children: []) == KeySource<Void>("", children: []).snapshot(for: ())
        )
        #expect(first != KeySource<Void>("title", value: "content").snapshot(for: ()))
    }

    @Test func documentExportConsumerReusesOnlyEquivalentSemanticInputs() throws {
        var cache = MemoizationCache<DependencySnapshot, String>(capacity: 16)
        var computations = 0

        func export(_ document: Document, options: ExportOptions) throws -> String {
            let paragraphs = document.paragraphs
            let key = try DependencySnapshot(children: [
                DependencySnapshot(value: paragraphs), DependencySnapshot(value: options),
            ])
            return cache.value(for: key) {
                computations += 1
                let heading =
                    options.includesHeading ? (options.format == .markdown ? "# Document\n" : "Document\n") : ""
                return heading + paragraphs.joined(separator: "\n")
            }
        }

        let contents = [[String](), ["First"], ["First", "Second"]]
        for paragraphs in contents {
            for format in ExportFormat.allCases {
                for includesHeading in [false, true] {
                    let options = ExportOptions(format: format, includesHeading: includesHeading)
                    var document = Document(paragraphs: paragraphs, scrollOffset: 0)
                    let before = computations
                    let first = try export(document, options: options)
                    let heading = includesHeading ? (format == .markdown ? "# Document\n" : "Document\n") : ""
                    #expect(first == heading + paragraphs.joined(separator: "\n"))
                    #expect(computations == before + 1)
                    document.selectedParagraph = 0
                    document.scrollOffset = 100
                    #expect(try export(document, options: options) == first)
                    #expect(computations == before + 1)
                }
            }
        }
        #expect(computations == 12)
        #expect(cache.count == 12)
    }
}
