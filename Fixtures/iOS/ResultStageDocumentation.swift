import DerivedKeysUIExample
import UIKit

// Normal-import consumer of the complete application example linked from the guide.
@MainActor
final class ResultStageExampleScreen {
    private let measurements = ResultBasedRowMeasurements()
    private let row = PlainTextRowView()

    func size(for text: String, width: CGFloat) -> CGSize {
        row.text = text
        return measurements.size(of: row, toFit: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }
}
