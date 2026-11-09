/// An error from building a fitting proposal.
public enum FittingProposalError: Error, Equatable, Sendable {
    /// A dimension is negative, NaN, or an infinity the initializer does not accept.
    case invalidDimension
}

/// A finite nonnegative bound in points, or no bound at all.
///
/// Zero is a real bound and is not equal to ``unconstrained``. See <doc:CacheContract> for how
/// caches normalize and key proposals.
public struct FittingDimension: Hashable, Sendable {
    /// The absence of a bound.
    public static let unconstrained = Self(storage: nil)

    private let storage: Double?

    /// The bound in points, or `nil` when unconstrained.
    public var limit: Double? {
        storage
    }

    /// Creates a finite nonnegative bound without rounding it.
    ///
    /// Both signs of zero produce the same bound. Use ``unconstrained`` rather than infinity
    /// to express no bound.
    /// - Throws: ``FittingProposalError/invalidDimension`` for negative, NaN, or infinite points.
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
