/// Invalid input at the fitting-proposal boundary.
public enum FittingProposalError: Error, Equatable, Sendable {
    /// A dimension is negative or nonfinite.
    case invalidDimension
}

/// A finite nonnegative bound in points, or an explicit absence of a bound.
///
/// Equality preserves exact bounds and distinguishes zero from an unconstrained dimension.
public struct FittingDimension: Hashable, Sendable {
    /// An unconstrained dimension.
    public static let unconstrained = Self(storage: nil)

    private let storage: Double?

    /// The bound in points, or `nil` when unconstrained.
    public var limit: Double? {
        storage
    }

    /// Creates a finite nonnegative bound without quantization.
    ///
    /// Both signs of zero produce the same bound. Infinity does not represent
    /// an unconstrained dimension.
    /// - Throws: `FittingProposalError.invalidDimension` for negative or nonfinite points.
    public init(points: Double) throws {
        guard points.isFinite, points >= 0 else {
            throw FittingProposalError.invalidDimension
        }
        storage = points == 0 ? 0 : points
    }

    private init(storage: Double?) {
        self.storage = storage
    }
}
