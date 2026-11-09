import CoreGraphics

/// The width and height available to a layout calculation.
///
/// A proposal is part of every ``LayoutCache`` key and is passed to its calculation unchanged.
/// It does not round, clamp, or otherwise constrain the calculated result; see
/// <doc:CacheContract>.
public struct FittingProposal: Hashable, Sendable {
    /// The horizontal bound.
    public let width: FittingDimension
    /// The vertical bound.
    public let height: FittingDimension

    /// The size to pass to UIKit, with unconstrained axes as `CGFloat.greatestFiniteMagnitude`.
    ///
    /// ``init(fitting:)`` reserves that value as the unbounded sentinel, so an explicit bound
    /// equal to it does not round-trip as a bounded dimension.
    public var fittingSize: CGSize {
        CGSize(
            width: width.limit.map { CGFloat($0) } ?? .greatestFiniteMagnitude,
            height: height.limit.map { CGFloat($0) } ?? .greatestFiniteMagnitude
        )
    }

    /// Creates a proposal from a width and an optional height bound.
    ///
    /// The height is unconstrained unless you supply one.
    public init(width: FittingDimension, height: FittingDimension = .unconstrained) {
        self.width = width
        self.height = height
    }

    /// Creates a proposal from a UIKit fitting size without rounding it.
    ///
    /// An axis equal to `CGFloat.greatestFiniteMagnitude` or positive infinity becomes
    /// unconstrained. Any other axis must be finite and nonnegative.
    /// - Throws: ``FittingProposalError/invalidDimension`` for a negative, NaN, or
    ///   negative-infinity axis.
    public init(fitting size: CGSize) throws {
        func dimension(_ points: CGFloat) throws -> FittingDimension {
            if points == .greatestFiniteMagnitude || points == .infinity {
                return .unconstrained
            }
            return try FittingDimension(points: Double(points))
        }
        self.init(width: try dimension(size.width), height: try dimension(size.height))
    }
}
