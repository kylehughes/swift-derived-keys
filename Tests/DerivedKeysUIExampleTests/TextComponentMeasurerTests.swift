#if canImport(UIKit)
import DerivedKeysUIExample
import DerivedKeysUIKit
import Testing
import UIKit

@MainActor
struct TextComponentMeasurerTests {
    private func font(size: Double = 17) throws -> MeasurementFont {
        try MeasurementFont(name: "Helvetica", pointSize: size)
    }

    private func input(
        text: String = "A long paragraph with enough words to wrap across several lines in a narrow container.",
        button: ButtonMeasurementInput? = nil,
        spacing: Double = 8
    ) throws -> TextComponentInput {
        try TextComponentInput(
            text: TextMeasurementInput(text: text, font: font()),
            button: button,
            padding: MeasurementInsets(top: 3, left: 4, bottom: 3, right: 4),
            spacing: spacing
        )
    }

    private func proposal(width: Double, height: FittingDimension = .unconstrained) throws -> FittingProposal {
        try FittingProposal(width: FittingDimension(points: width), height: height)
    }

    @Test func fittingWidthIsAutomaticallyKeyedAndMeasured() throws {
        let measurer = TextComponentMeasurer(capacity: 8)
        let snapshot = try input()
        let context = try MeasurementContext(displayScale: 2)
        let narrow = try proposal(width: 100)
        let wide = try proposal(width: 300)
        #expect(
            measurer.key(for: snapshot, proposal: narrow, context: context)
                != measurer.key(for: snapshot, proposal: wide, context: context)
        )
        let narrowSize = measurer.size(for: snapshot, proposal: narrow, context: context)
        let wideSize = measurer.size(for: snapshot, proposal: wide, context: context)
        #expect(narrowSize.height > wideSize.height)
        #expect(narrowSize.width <= 100)
        #expect(wideSize.width <= 300)
        _ = measurer.size(for: snapshot, proposal: narrow, context: context)
        #expect(measurer.textCalculationCount == 2)
        #expect(measurer.componentCalculationCount == 2)
    }

    @Test func unchangedEntityIdentityDoesNotHideChangedContent() throws {
        struct Model {
            let id: Int
            var text: String
            var color: UIColor
            var url: String
            var action: () -> Void
        }
        var model = Model(id: 42, text: "Short", color: .red, url: "first", action: {})
        let measurer = TextComponentMeasurer(capacity: 8)
        let bounds = try proposal(width: 120)
        let context = try MeasurementContext(displayScale: 2)
        let initial = try input(text: model.text)
        let initialKey = measurer.key(for: initial, proposal: bounds, context: context)
        _ = measurer.size(for: initial, proposal: bounds, context: context)
        model.color = .blue
        model.url = "second"
        model.action = { _ = 1 + 1 }
        let irrelevantChange = try input(text: model.text)
        #expect(measurer.key(for: irrelevantChange, proposal: bounds, context: context) == initialKey)
        _ = measurer.size(for: irrelevantChange, proposal: bounds, context: context)
        #expect(measurer.componentCalculationCount == 1)
        model.text = "A much longer text value under the same entity ID, wrapping onto several lines."
        #expect(model.id == 42)
        let changed = try input(text: model.text)
        #expect(measurer.key(for: changed, proposal: bounds, context: context) != initialKey)
        _ = measurer.size(for: changed, proposal: bounds, context: context)
        #expect(measurer.textCalculationCount == 2)
    }

    @Test func optionalButtonCachesIndependentlyAndRestoresPreviousKey() throws {
        let measurer = TextComponentMeasurer(capacity: 8)
        let bounds = try proposal(width: 180)
        let context = try MeasurementContext(displayScale: 2)
        let hidden = try input()
        let visible = try input(button: ButtonMeasurementInput(title: "Expand", font: font(), style: .padded))
        let hiddenKey = measurer.key(for: hidden, proposal: bounds, context: context)
        let visibleKey = measurer.key(for: visible, proposal: bounds, context: context)
        #expect(hiddenKey != visibleKey)
        #expect(hiddenKey.dependencies.text == visibleKey.dependencies.text)
        #expect(hiddenKey.dependencies.button == nil)
        let hiddenSize = measurer.size(for: hidden, proposal: bounds, context: context)
        let visibleSize = measurer.size(for: visible, proposal: bounds, context: context)
        #expect(visibleSize.height > hiddenSize.height)
        let otherTitle = try input(
            button: ButtonMeasurementInput(title: "Show more content", font: font(), style: .padded)
        )
        _ = measurer.size(for: otherTitle, proposal: bounds, context: context)
        #expect(measurer.textCalculationCount == 1)
        #expect(measurer.buttonCalculationCount == 2)
        #expect(measurer.size(for: hidden, proposal: bounds, context: context) == hiddenSize)
        #expect(measurer.key(for: hidden, proposal: bounds, context: context) == hiddenKey)
        #expect(measurer.componentCalculationCount == 3)
        // A hidden button's title/font/style never enter the snapshot. Parent-only spacing is ignored too.
        let changedHiddenSpacing = try input(spacing: 900)
        #expect(measurer.key(for: changedHiddenSpacing, proposal: bounds, context: context) == hiddenKey)
        let hiddenButtonMetrics = try ButtonMeasurementInput(
            title: "Entirely different title",
            font: font(size: 30),
            style: .plain
        )
        func snapshot(button: ButtonMeasurementInput, isVisible: Bool) throws -> TextComponentInput {
            try input(button: isVisible ? button : nil)
        }
        let hiddenChangedMetrics = try snapshot(button: hiddenButtonMetrics, isVisible: false)
        #expect(measurer.key(for: hiddenChangedMetrics, proposal: bounds, context: context) == hiddenKey)
    }

    @Test func equivalentViewsAndReusedViewUseContentInsteadOfViewIdentity() throws {
        let first = UILabel()
        let second = UILabel()
        first.text = "Equal content"
        second.text = "Equal content"
        let measurer = TextComponentMeasurer(capacity: 8)
        let bounds = try proposal(width: 180)
        let context = try MeasurementContext(displayScale: 3)
        let firstSnapshot = try input(text: first.text ?? "")
        let secondSnapshot = try input(text: second.text ?? "")
        #expect(
            measurer.key(for: firstSnapshot, proposal: bounds, context: context)
                == measurer.key(for: secondSnapshot, proposal: bounds, context: context)
        )
        _ = measurer.size(for: firstSnapshot, proposal: bounds, context: context)
        _ = measurer.size(for: secondSnapshot, proposal: bounds, context: context)
        #expect(measurer.componentCalculationCount == 1)
        first.text = "Reused with different content"
        #expect(
            measurer.key(for: try input(text: first.text ?? ""), proposal: bounds, context: context)
                != measurer.key(for: firstSnapshot, proposal: bounds, context: context)
        )
    }

    @Test func heightScaleTypographyAndLinePolicyAreDependencies() throws {
        let measurer = TextComponentMeasurer(capacity: 8)
        let context = try MeasurementContext(displayScale: 3)
        let bounds = try proposal(width: 160, height: FittingDimension(points: 20.1))
        let original = try input()
        let key = measurer.key(for: original, proposal: bounds, context: context)
        let measured = measurer.size(for: original, proposal: bounds, context: context)
        #expect(measured.height <= 20.1)
        #expect(measurer.key(for: original, proposal: bounds, context: try MeasurementContext(displayScale: 2)) != key)
        let truncated = try TextComponentInput(
            text: TextMeasurementInput(
                text: original.text.text,
                font: font(size: 21),
                numberOfLines: 1,
                lineBreak: .truncatingTail
            ),
            padding: original.padding
        )
        #expect(measurer.key(for: truncated, proposal: bounds, context: context) != key)
        #expect(measurer.key(for: original, proposal: try proposal(width: 160), context: context) != key)
    }

    @Test func unconstrainedProposalMeasuresFiniteNaturalSize() throws {
        let measurer = TextComponentMeasurer(capacity: 8)
        let snapshot = try input(text: "Natural width", button: ButtonMeasurementInput(title: "More", font: font()))
        let bounds = FittingProposal(width: .unconstrained)
        let context = try MeasurementContext(displayScale: 2)
        let measured = measurer.size(for: snapshot, proposal: bounds, context: context)
        #expect(measured.width.isFinite && measured.width > 0)
        #expect(measured.height.isFinite && measured.height > 0)
        #expect(measurer.size(for: snapshot, proposal: bounds, context: context) == measured)
        #expect(measurer.componentCalculationCount == 1)
    }

    @Test func invalidUIKitInputsAreRejected() throws {
        #expect(throws: MeasurementInputError.invalidFont) { try font(size: .nan) }
        #expect(throws: MeasurementInputError.invalidFont) { try font(size: 0) }
        #expect(throws: MeasurementInputError.invalidFont) { try MeasurementFont(name: "No such font", pointSize: 17) }
        let resolved = try font()
        #expect(throws: MeasurementInputError.invalidLineCount) {
            try TextMeasurementInput(text: "Text", font: resolved, numberOfLines: -1)
        }
        #expect(throws: MeasurementInputError.invalidDimension) { try input(spacing: .infinity) }
    }
}
#endif
