/// Invalid input at the measurement adapter boundary.
public enum MeasurementInputError: Error, Equatable, Sendable {
    /// A dimension, inset, or spacing is invalid.
    case invalidDimension
    /// The display scale is not finite and positive.
    case invalidScale
    /// The font name or point size cannot be resolved.
    case invalidFont
    /// The line count is negative.
    case invalidLineCount
}

/// A finite nonnegative bound, or an explicit absence of a bound.
public struct FittingDimension: Hashable, Sendable {
    private let storage: Double?

    /// An unconstrained dimension, translated to UIKit's fitting sentinel by the adapter.
    public static let unconstrained = Self(storage: nil)

    /// The bound in points, or `nil` when unconstrained.
    public var limit: Double? {
        storage
    }

    /// Creates a finite nonnegative bound.
    ///
    /// Infinity is not an unconstrained spelling.
    public init(points: Double) throws {
        guard points.isFinite, points >= 0 else {
            throw MeasurementInputError.invalidDimension
        }
        storage = points == 0 ? 0 : points
    }

    private init(storage: Double?) {
        self.storage = storage
    }

    func subtracting(_ points: Double) -> Self {
        Self(
            storage: storage.map {
                max(0, $0 - points)
            }
        )
    }
}

/// The exact bounds used both in request keys and in the sizing calculation.
public struct FittingProposal: Hashable, Sendable {
    /// The available horizontal extent.
    public let width: FittingDimension
    /// The available vertical extent.
    public let height: FittingDimension

    /// Creates a proposal with an unconstrained height unless one is supplied.
    public init(width: FittingDimension, height: FittingDimension = .unconstrained) {
        self.width = width
        self.height = height
    }
}

/// Finite nonnegative layout insets, measured in points.
public struct MeasurementInsets: Hashable, Sendable {
    private let storedTop: Double
    private let storedLeft: Double
    private let storedBottom: Double
    private let storedRight: Double

    /// The top inset in points.
    public var top: Double {
        storedTop
    }
    /// The left inset in points.
    public var left: Double {
        storedLeft
    }
    /// The bottom inset in points.
    public var bottom: Double {
        storedBottom
    }
    /// The right inset in points.
    public var right: Double {
        storedRight
    }

    /// Creates nonnegative finite insets whose horizontal and vertical totals remain finite.
    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) throws {
        guard
            [top, left, bottom, right]
                .allSatisfy({
                    $0.isFinite && $0 >= 0
                }),
            (top + bottom).isFinite, (left + right).isFinite
        else {
            throw MeasurementInputError.invalidDimension
        }
        storedTop = top
        storedLeft = left
        storedBottom = bottom
        storedRight = right
    }
}

/// Explicit display scale used for pixel rounding; no ambient screen is consulted.
public struct MeasurementContext: Hashable, Sendable {
    private let storedDisplayScale: Double

    /// The finite positive number of pixels per point.
    public var displayScale: Double {
        storedDisplayScale
    }

    /// Creates a context with a finite positive display scale.
    public init(displayScale: Double) throws {
        guard displayScale.isFinite, displayScale > 0 else {
            throw MeasurementInputError.invalidScale
        }
        storedDisplayScale = displayScale
    }
}
