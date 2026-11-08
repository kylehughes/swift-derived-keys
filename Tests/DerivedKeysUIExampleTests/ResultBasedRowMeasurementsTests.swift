#if canImport(UIKit)
import DerivedKeysUIExample
import Testing
import UIKit

@MainActor
struct ResultBasedRowMeasurementsTests {
    @Test func differentTextsWithTheSameLineCountShareOnlyTheHeightEntry() {
        let measurements = ResultBasedRowMeasurements()
        let first = measurements.height(for: "First", width: 300)
        #expect(first == 40)
        #expect(measurements.height(for: "Second", width: 300) == first)
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.lineCountEntryCount == 2)
        #expect(measurements.rowHeightEntryCount == 1)

        #expect(measurements.height(for: "First", width: 300) == first)
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.rowHeightEntryCount == 1)
    }

    @Test(arguments: [
        (text: "", count: 0),
        (text: "One", count: 1),
        (text: "One\nTwo", count: 2),
        (text: "One\n", count: 2),
        (text: "\n", count: 2),
        (text: "One\n\n", count: 3),
    ])
    func emptyTextAndHardBreaksFollowTheFixedLineGrid(fixture: (text: String, count: Int)) {
        let measurements = ResultBasedRowMeasurements()
        let count = measurements.lineCount(for: fixture.text, width: 300)
        #expect(count == fixture.count)
        #expect(count == directLineCount(text: fixture.text, width: 300))
        #expect(measurements.height(for: fixture.text, width: 300) == CGFloat(fixture.count) * 24 + 16)
        #expect(measurements.lineCountCalculationCount == 1)
    }

    @Test func fixedTypographyAndPaddingBelongToTheBundle() {
        let font = UIFont.systemFont(ofSize: 22)
        let measurements = ResultBasedRowMeasurements(font: font, lineHeight: 36, verticalPadding: 10)
        let text = "First line\nSecond line\n"
        let count = directLineCount(text: text, width: 300, font: font, lineHeight: 36)
        #expect(count == 3)
        #expect(measurements.lineCount(for: text, width: 300) == count)
        #expect(measurements.height(for: text, width: 300) == 118)
        #expect(measurements.font == font)
        #expect(measurements.lineHeight == 36)
        #expect(measurements.verticalPadding == 10)
    }

    @Test func independentCapacitiesBoundEachStage() {
        let measurements = ResultBasedRowMeasurements(lineCountCapacity: 1, rowHeightCapacity: 2)
        _ = measurements.height(for: "One", width: 300)
        _ = measurements.height(for: "Two", width: 300)
        #expect(measurements.lineCountEntryCount == 1)
        #expect(measurements.rowHeightEntryCount == 1)
        _ = measurements.height(for: "One", width: 300)
        #expect(measurements.lineCountCalculationCount == 3)
        _ = measurements.height(for: "One\nTwo", width: 300)
        _ = measurements.height(for: "One\nTwo\nThree", width: 300)
        #expect(measurements.lineCountEntryCount == 1)
        #expect(measurements.rowHeightEntryCount == 2)
    }

    @Test func modelStringMutationSelectsItsNewValueWithoutAViewReadback() {
        struct Row {
            let id: Int
            var text: String
        }
        var row = Row(id: 7, text: "Original")
        let original = row.text
        let measurements = ResultBasedRowMeasurements()
        #expect(measurements.height(for: row.text, width: 300) == 40)
        row.text.append("\nAdded")
        #expect(row.id == 7)
        #expect(measurements.height(for: row.text, width: 300) == 64)
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.rowHeightEntryCount == 2)
        row.text = original
        #expect(measurements.height(for: row.text, width: 300) == 40)
        #expect(measurements.lineCountCalculationCount == 2)
    }

    @Test func widthAndTextChangesRecomputeActualTextKitWrapping() {
        let measurements = ResultBasedRowMeasurements()
        let text = "Several words wrap across many lines when the available width becomes narrow."
        let narrow = measurements.lineCount(for: text, width: 90)
        let wide = measurements.lineCount(for: text, width: 400)
        #expect(narrow > wide)
        #expect(wide > 1)
        #expect(narrow == directLineCount(text: text, width: 90))
        #expect(wide == directLineCount(text: text, width: 400))
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.height(for: text, width: 90) == CGFloat(narrow) * 24 + 16)
        #expect(measurements.height(for: text, width: 400) == CGFloat(wide) * 24 + 16)
        #expect(measurements.lineCountCalculationCount == 2)

        let changed = text + "\n"
        let changedCount = measurements.lineCount(for: changed, width: 90)
        #expect(changedCount == narrow + 1)
        #expect(changedCount == directLineCount(text: changed, width: 90))
        #expect(measurements.lineCountCalculationCount == 3)
    }

    @Test func zeroCapacitiesComputeWithoutRetainingEntries() {
        let measurements = ResultBasedRowMeasurements(lineCountCapacity: 0, rowHeightCapacity: 0)
        #expect(measurements.height(for: "Text", width: 300) == 40)
        #expect(measurements.height(for: "Text", width: 300) == 40)
        #expect(measurements.lineCountCalculationCount == 2)
        #expect(measurements.lineCountEntryCount == 0)
        #expect(measurements.rowHeightEntryCount == 0)
    }

    /// An uncached control walks effective glyph ranges rather than the example's enumeration callback.
    private func directLineCount(
        text: String,
        width: CGFloat,
        font: UIFont = .systemFont(ofSize: 16),
        lineHeight: CGFloat = 24
    ) -> Int {
        guard !text.isEmpty else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let storage = NSTextStorage(
            string: text,
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        let layout = NSLayoutManager()
        layout.usesFontLeading = false
        let container = NSTextContainer(size: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        var count = 0
        var index = 0
        while index < layout.numberOfGlyphs {
            var range = NSRange()
            _ = layout.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
            index = NSMaxRange(range)
            count += 1
        }
        if layout.extraLineFragmentTextContainer === container {
            count += 1
        }
        return count
    }
}
#endif
