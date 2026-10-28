import CoreGraphics
import DerivedKeysUIKit
import Testing

struct FittingProposalTests {
    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func invalidDimensionsAreRejected(points: Double) {
        #expect(throws: FittingProposalError.invalidDimension) {
            try FittingDimension(points: points)
        }
    }

    @Test func zeroAndUnconstrainedAreDistinct() throws {
        let zero = try FittingDimension(points: 0)
        let negativeZero = try FittingDimension(points: -0.0)
        #expect(zero.limit == 0)
        #expect(negativeZero == zero)
        #expect(negativeZero.limit?.sign == .plus)
        #expect(FittingDimension.unconstrained.limit == nil)
        #expect(zero != .unconstrained)
        #expect(Set([zero, negativeZero, .unconstrained]).count == 2)
    }

    @Test func finiteBoundsArePreservedWithoutQuantization() throws {
        let width = try FittingDimension(points: 123.125)
        let height = try FittingDimension(points: .leastNonzeroMagnitude)
        let proposal = FittingProposal(width: width, height: height)
        #expect(proposal.width.limit == 123.125)
        #expect(proposal.height.limit == .leastNonzeroMagnitude)
        #expect(FittingProposal(width: width).height == .unconstrained)
        #expect(try FittingDimension(points: .greatestFiniteMagnitude).limit == .greatestFiniteMagnitude)
    }

    @Test(arguments: [CGFloat.nan, .infinity, -.infinity, -1])
    func fittingBridgeRejectsInvalidAxes(points: CGFloat) {
        #expect(throws: FittingProposalError.invalidDimension) {
            try FittingProposal(fitting: CGSize(width: points, height: 12))
        }
        #expect(throws: FittingProposalError.invalidDimension) {
            try FittingProposal(fitting: CGSize(width: 12, height: points))
        }
    }

    @Test func fittingBridgePreservesFiniteSizesAndZero() throws {
        let size = CGSize(width: 123.125, height: 89.375)
        let proposal = try FittingProposal(fitting: size)
        #expect(proposal.width.limit == Double(size.width))
        #expect(proposal.height.limit == Double(size.height))
        #expect(proposal.fittingSize == size)
        #expect(try FittingProposal(fitting: proposal.fittingSize) == proposal)
        let zero = try FittingProposal(fitting: .zero)
        #expect(zero.width.limit == 0)
        #expect(zero.height.limit == 0)
        #expect(zero.fittingSize == .zero)
    }

    @Test func fittingBridgeMapsEachSentinelAxisIndependently() throws {
        let width = try FittingProposal(fitting: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 30))
        #expect(width.width == .unconstrained)
        #expect(width.height.limit == 30)
        #expect(width.fittingSize == CGSize(width: CGFloat.greatestFiniteMagnitude, height: 30))
        let height = try FittingProposal(fitting: CGSize(width: 40, height: CGFloat.greatestFiniteMagnitude))
        #expect(height.width.limit == 40)
        #expect(height.height == .unconstrained)
        #expect(height.fittingSize == CGSize(width: 40, height: CGFloat.greatestFiniteMagnitude))
        let unbounded = FittingProposal(width: .unconstrained)
        #expect(try FittingProposal(fitting: unbounded.fittingSize) == unbounded)
    }

    @Test func greatestFiniteBoundUsesTheReservedBridgeSentinel() throws {
        let bound = try FittingDimension(points: Double(CGFloat.greatestFiniteMagnitude))
        let bounded = FittingProposal(width: bound)
        #expect(bounded.width != .unconstrained)
        let bridged = try FittingProposal(fitting: bounded.fittingSize)
        #expect(bridged.width == .unconstrained)
        #expect(bridged != bounded)
    }
}
