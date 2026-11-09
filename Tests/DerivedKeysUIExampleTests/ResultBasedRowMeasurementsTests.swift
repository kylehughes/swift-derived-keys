#if canImport(UIKit)
import DerivedKeysUIExample
import Testing
import UIKit

@MainActor
struct ResultBasedRowMeasurementsTests {
    @Test func equalLineCountsShareSizesAcrossDistinctStringsAndViews() {
        let measurements = ResultBasedRowMeasurements()
        let first = PlainTextRowView(text: "First")
        let second = PlainTextRowView(text: "Second")
        let proposal = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        let expectedFirst = directSize(of: first, toFit: proposal)
        let expectedSecond = directSize(of: second, toFit: proposal)
        #expect(expectedFirst == expectedSecond)
        #expect(measurements.size(of: first, toFit: proposal) == expectedFirst)
        #expect(first.sizeThatFitsCallCount == 1)
        #expect(measurements.size(of: second, toFit: proposal) == expectedSecond)
        #expect(second.sizeThatFitsCallCount == 0)
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.lineCountEntryCount == 2)
        #expect(measurements.rowSizeEntryCount == 1)

        #expect(measurements.size(of: first, toFit: proposal) == expectedFirst)
        #expect(first.sizeThatFitsCallCount == 1)
        #expect(measurements.lineCountCalculationCount == 2)
    }

    @Test(arguments: [
        (text: "", count: 1),
        (text: "One", count: 1),
        (text: "One\nTwo", count: 2),
        (text: "One\n", count: 2),
        (text: "\n", count: 2),
        (text: "One\n\n", count: 3),
    ])
    func countsRenderedFragmentsAndFinalEmptyLines(fixture: (text: String, count: Int)) {
        let measurements = ResultBasedRowMeasurements()
        let row = PlainTextRowView(text: fixture.text)
        let proposal = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        #expect(measurements.lineCount(for: row.text, width: 300, font: row.font) == fixture.count)
        #expect(measurements.size(of: row, toFit: proposal) == directSize(of: row, toFit: proposal))
        #expect(measurements.lineCountCalculationCount == 1)
        #expect(row.sizeThatFitsCallCount == 1)
    }

    @Test func representativePlainTextMatchesDirectViewMeasurementAcrossCounts() {
        let measurements = ResultBasedRowMeasurements()
        let proposal = CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
        for text in [
            "", "Short", "Wider words", "One\nTwo", "One\n", "One\n\n",
            "Several words wrap across many lines when the available width becomes narrow.",
            "😀 👨‍👩‍👧‍👦", "😀\n😀", "中文排版示例", "مرحبا بالعالم", "नमस्ते दुनिया", "ภาษาไทย",
        ] {
            let row = PlainTextRowView(text: text, horizontalPadding: 6, verticalPadding: 9)
            #expect(measurements.size(of: row, toFit: proposal) == directSize(of: row, toFit: proposal))
        }
        #expect(measurements.lineCountEntryCount == 13)
        #expect(measurements.rowSizeEntryCount > 1)
        #expect(measurements.rowSizeEntryCount < measurements.lineCountEntryCount)
    }

    @Test func textMutationSynchronizesTheViewAndRestorationReusesBothStages() {
        let measurements = ResultBasedRowMeasurements()
        let row = PlainTextRowView(text: "Original")
        let proposal = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        let original = measurements.size(of: row, toFit: proposal)
        row.text.append("\nAdded")
        let changed = measurements.size(of: row, toFit: proposal)
        #expect(changed == directSize(of: row, toFit: proposal))
        #expect(changed.height > original.height)
        #expect(row.sizeThatFitsCallCount == 2)
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.rowSizeEntryCount == 2)
        row.text = "Original"
        #expect(measurements.size(of: row, toFit: proposal) == original)
        #expect(row.sizeThatFitsCallCount == 2)
        #expect(measurements.lineCountCalculationCount == 2)
    }

    @Test func widthChangesAreKeyedEvenWhenTheLineCountStaysTheSame() {
        let measurements = ResultBasedRowMeasurements()
        let row = PlainTextRowView(text: "Text", horizontalPadding: 8)
        let narrow = CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        let wide = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        let narrowSize = measurements.size(of: row, toFit: narrow)
        let wideSize = measurements.size(of: row, toFit: wide)
        #expect(narrowSize == directSize(of: row, toFit: narrow))
        #expect(wideSize == directSize(of: row, toFit: wide))
        #expect(narrowSize.width == narrow.width)
        #expect(wideSize.width == wide.width)
        #expect(narrowSize.height == wideSize.height)
        #expect(measurements.lineCount(for: row.text, width: 184, font: row.font) == 1)
        #expect(measurements.lineCount(for: row.text, width: 284, font: row.font) == 1)
        #expect(row.sizeThatFitsCallCount == 2)
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.rowSizeEntryCount == 2)
    }

    @Test func narrowerWidthsChangeActualWrapping() {
        let measurements = ResultBasedRowMeasurements()
        let row = PlainTextRowView(text: "Several words wrap across many lines at a narrow available width.")
        let narrow = CGSize(width: 90, height: CGFloat.greatestFiniteMagnitude)
        let wide = CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        let narrowSize = measurements.size(of: row, toFit: narrow)
        let wideSize = measurements.size(of: row, toFit: wide)
        #expect(narrowSize == directSize(of: row, toFit: narrow))
        #expect(wideSize == directSize(of: row, toFit: wide))
        #expect(narrowSize.height > wideSize.height)
        #expect(
            measurements.lineCount(for: row.text, width: 90, font: row.font)
                > measurements.lineCount(for: row.text, width: 400, font: row.font)
        )
        #expect(measurements.lineCountCalculationCount == 2)
    }

    @Test func fontChangesInvalidateBothStagesEvenWithEqualLineCounts() {
        let measurements = ResultBasedRowMeasurements()
        let row = PlainTextRowView(text: "Text")
        let proposal = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        let original = measurements.size(of: row, toFit: proposal)
        row.font = .systemFont(ofSize: 28)
        let changed = measurements.size(of: row, toFit: proposal)
        #expect(changed == directSize(of: row, toFit: proposal))
        #expect(changed.height > original.height)
        #expect(measurements.lineCount(for: row.text, width: 300, font: row.font) == 1)
        #expect(row.sizeThatFitsCallCount == 2)
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.rowSizeEntryCount == 2)
    }

    @Test func paddingChangesUseTheSameInnerWidthInBothStages() {
        let measurements = ResultBasedRowMeasurements()
        let row = PlainTextRowView(text: "Text")
        let proposal = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        let original = measurements.size(of: row, toFit: proposal)
        row.verticalPadding = 14
        let vertical = measurements.size(of: row, toFit: proposal)
        #expect(vertical == directSize(of: row, toFit: proposal))
        #expect(vertical.height > original.height)
        #expect(measurements.lineCountCalculationCount == 1)
        row.horizontalPadding = 20
        #expect(measurements.size(of: row, toFit: proposal) == directSize(of: row, toFit: proposal))
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.lineCount(for: row.text, width: 260, font: row.font) == 1)
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.rowSizeEntryCount == 3)
        #expect(row.sizeThatFitsCallCount == 3)
    }

    @Test func proposedHeightParticipatesInTheSizeKey() {
        let measurements = ResultBasedRowMeasurements()
        let row = PlainTextRowView(text: "Text")
        let first = measurements.size(of: row, toFit: CGSize(width: 300, height: 100))
        let second = measurements.size(of: row, toFit: CGSize(width: 300, height: 200))
        #expect(first == second)
        #expect(row.sizeThatFitsCallCount == 2)
        #expect(measurements.lineCountCalculationCount == 1)
        #expect(measurements.rowSizeEntryCount == 2)
    }

    @Test func independentlyBoundedStagesEvictTheirOwnEntries() {
        let measurements = ResultBasedRowMeasurements(lineCountCapacity: 1, rowSizeCapacity: 2)
        let row = PlainTextRowView(text: "One")
        let proposal = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        let original = measurements.size(of: row, toFit: proposal)
        row.text = "Two"
        #expect(measurements.size(of: row, toFit: proposal) == original)
        row.text = "One"
        #expect(measurements.size(of: row, toFit: proposal) == original)
        #expect(measurements.lineCountCalculationCount == 3)
        #expect(row.sizeThatFitsCallCount == 1)
        #expect(measurements.lineCountEntryCount == 1)
        row.text = "One\nTwo"
        _ = measurements.size(of: row, toFit: proposal)
        row.text = "One\nTwo\nThree"
        _ = measurements.size(of: row, toFit: proposal)
        #expect(measurements.rowSizeEntryCount == 2)
        row.text = "One"
        #expect(measurements.size(of: row, toFit: proposal) == original)
        #expect(row.sizeThatFitsCallCount == 4)
        #expect(measurements.lineCountEntryCount == 1)
        #expect(measurements.rowSizeEntryCount == 2)
    }

    @Test(arguments: [(line: 0, size: 2), (line: 2, size: 0), (line: 0, size: 0)])
    func zeroCapacityDisablesOnlyThatStagesStorage(capacities: (line: Int, size: Int)) {
        let measurements = ResultBasedRowMeasurements(
            lineCountCapacity: capacities.line,
            rowSizeCapacity: capacities.size
        )
        let row = PlainTextRowView(text: "Text")
        let proposal = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        let expected = directSize(of: row, toFit: proposal)
        #expect(measurements.size(of: row, toFit: proposal) == expected)
        #expect(measurements.size(of: row, toFit: proposal) == expected)
        #expect(measurements.lineCountCalculationCount == (capacities.line == 0 ? 2 : 1))
        #expect(row.sizeThatFitsCallCount == (capacities.size == 0 ? 2 : 1))
        #expect(measurements.lineCountEntryCount == (capacities.line == 0 ? 0 : 1))
        #expect(measurements.rowSizeEntryCount == (capacities.size == 0 ? 0 : 1))
    }

    /// Measures an equivalent uncached view without changing the observed row's call counter.
    private func directSize(of row: PlainTextRowView, toFit proposal: CGSize) -> CGSize {
        PlainTextRowView(
            text: row.text,
            font: row.font,
            horizontalPadding: row.horizontalPadding,
            verticalPadding: row.verticalPadding
        )
        .sizeThatFits(proposal)
    }
}
#endif
