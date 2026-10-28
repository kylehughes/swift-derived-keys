import DerivedKeysUIExample
import Testing

struct FittingProposalTests {
    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func invalidDimensionsAreRejected(points: Double) {
        #expect(throws: MeasurementInputError.invalidDimension) {
            try FittingDimension(points: points)
        }
        #expect(throws: MeasurementInputError.invalidDimension) {
            try MeasurementInsets(left: points)
        }
    }

    @Test func explicitUnboundedAndZeroAreDistinct() throws {
        let zero = try FittingDimension(points: 0)
        #expect(zero.limit == 0)
        #expect(FittingDimension.unconstrained.limit == nil)
        #expect(zero != .unconstrained)
        #expect(try FittingDimension(points: -0.0) == zero)
        #expect(try FittingDimension(points: 32).limit == 32)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, 0, -1])
    func invalidScaleIsRejected(scale: Double) {
        #expect(throws: MeasurementInputError.invalidScale) {
            try MeasurementContext(displayScale: scale)
        }
    }

    @Test func finiteInsetsCannotOverflowTheirTotals() {
        #expect(throws: MeasurementInputError.invalidDimension) {
            try MeasurementInsets(left: .greatestFiniteMagnitude, right: .greatestFiniteMagnitude)
        }
    }
}
