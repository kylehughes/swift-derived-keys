import CoreGraphics

/// The exact bounds captured in a layout key and passed to its calculation.
///
/// Proposals do not round, clamp, or otherwise constrain the calculated result.
public struct FittingProposal: Hashable, Sendable {
    /// The available horizontal extent.
    public let width: FittingDimension
    /// The available vertical extent.
    public let height: FittingDimension

    /// The framework fitting size, with unconstrained axes represented by `CGFloat.greatestFiniteMagnitude`.
    ///
    /// The greatest finite value is reserved as the unbounded sentinel by `init(fitting:)`.
    /// An explicit bound at that value therefore does not round-trip as a bounded dimension.
    public var fittingSize: CGSize {
        CGSize(
            width: width.limit.map { CGFloat($0) } ?? .greatestFiniteMagnitude,
            height: height.limit.map { CGFloat($0) } ?? .greatestFiniteMagnitude
        )
    }

    /// Creates a proposal with an unconstrained height unless one is supplied.
    public init(width: FittingDimension, height: FittingDimension = .unconstrained) {
        self.width = width
        self.height = height
    }

    /// Creates a proposal from a framework fitting size without quantization.
    ///
    /// Each axis equal to `CGFloat.greatestFiniteMagnitude` becomes unconstrained.
    /// Other axes must be finite and nonnegative; infinity is rejected.
    /// - Throws: `FittingProposalError.invalidDimension` for a negative or nonfinite axis.
    public init(fitting size: CGSize) throws {
        func dimension(_ points: CGFloat) throws -> FittingDimension {
            if points == .greatestFiniteMagnitude {
                return .unconstrained
            }
            return try FittingDimension(points: Double(points))
        }
        self.init(width: try dimension(size.width), height: try dimension(size.height))
    }
}
