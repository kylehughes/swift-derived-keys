import DerivedKeysUIExample
import UIKit

// Normal-import consumer of the complete application example linked from the guide.
@MainActor
final class ResultStageExampleScreen {
    private let measurements = ResultBasedRowMeasurements()

    func height(for text: String, width: CGFloat) -> CGFloat {
        measurements.height(for: text, width: width)
    }
}
